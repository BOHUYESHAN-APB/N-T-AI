from __future__ import annotations

import asyncio
import json
import math
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple

from sqlmodel import Session, select

from app.models.database import MemoryPoint, Person, engine
from app.services.llm_service import LLMService
from app.services.memory_system_service import MemorySystemService
from app.services.person_service import PersonService


def _normalize_item_name(name: str | None) -> str:
    if not name:
        return ""
    if name.startswith("minecraft:"):
        return name.split(":", 1)[1]
    return name


def _normalize_item_id(item_id: str | None) -> str:
    return _normalize_item_name(item_id)


@dataclass
class ItemStack:
    item_id: str
    name: str
    count: int
    max_count: int


@dataclass
class SlotInfo:
    slot: int
    group: str
    inv_index: int
    x: int
    y: int
    item: Optional[ItemStack]
    equip: Optional[str]


@dataclass
class ScreenSnapshot:
    handler: str
    screen_open: bool
    title: Optional[str]
    cursor: Optional[ItemStack]
    slots: List[SlotInfo]

    @classmethod
    def from_dict(cls, data: Dict[str, Any] | None) -> Optional["ScreenSnapshot"]:
        if not data or not isinstance(data, dict):
            return None
        slots_raw = data.get("slots")
        if not isinstance(slots_raw, list):
            return None
        slots: List[SlotInfo] = []
        for raw in slots_raw:
            if not isinstance(raw, dict):
                continue
            stack_raw = raw.get("stack")
            stack = None
            if isinstance(stack_raw, dict) and stack_raw.get("itemId"):
                item_id = stack_raw.get("itemId")
                stack = ItemStack(
                    item_id=item_id,
                    name=_normalize_item_id(item_id),
                    count=int(stack_raw.get("count", 0)),
                    max_count=int(stack_raw.get("maxCount", 0)),
                )
            slots.append(
                SlotInfo(
                    slot=int(raw.get("slot", -1)),
                    group=str(raw.get("group", "")),
                    inv_index=int(raw.get("invIndex", -1)),
                    x=int(raw.get("x", 0)),
                    y=int(raw.get("y", 0)),
                    item=stack,
                    equip=raw.get("equip"),
                )
            )
        cursor_raw = data.get("cursor")
        cursor = None
        if isinstance(cursor_raw, dict) and cursor_raw.get("itemId"):
            item_id = cursor_raw.get("itemId")
            cursor = ItemStack(
                item_id=item_id,
                name=_normalize_item_id(item_id),
                count=int(cursor_raw.get("count", 0)),
                max_count=int(cursor_raw.get("maxCount", 0)),
            )
        return cls(
            handler=str(data.get("handler", "")),
            screen_open=bool(data.get("screenOpen", False)),
            title=data.get("title"),
            cursor=cursor,
            slots=slots,
        )


@dataclass
class Recipe:
    result_name: str
    result_count: int
    shaped: bool
    shape: Optional[List[List[Optional[str]]]] = None
    ingredients: Optional[List[str]] = None


class RecipeBook:
    def __init__(self, data_root: Path) -> None:
        self._data_root = data_root
        self._recipes: Optional[Dict[str, List[Dict[str, Any]]]] = None
        self._id_to_name: Dict[int, str] = {}
        self._name_to_id: Dict[str, int] = {}

    def _ensure_loaded(self) -> None:
        if self._recipes is not None:
            return
        recipes_path = self._data_root / "recipes.json"
        items_path = self._data_root / "items.json"
        if not recipes_path.exists() or not items_path.exists():
            self._recipes = {}
            return
        with items_path.open("r", encoding="utf-8") as f:
            items = json.load(f)
        for item in items:
            item_id = int(item["id"])
            name = str(item["name"])
            self._id_to_name[item_id] = name
            self._name_to_id[name] = item_id
        with recipes_path.open("r", encoding="utf-8") as f:
            self._recipes = json.load(f)

    def get_recipes(self, item_name: str) -> List[Recipe]:
        self._ensure_loaded()
        if self._recipes is None:
            return []
        key = _normalize_item_name(item_name)
        item_id = self._name_to_id.get(key)
        if item_id is None:
            return []
        raw_list = self._recipes.get(str(item_id))
        if not isinstance(raw_list, list):
            return []
        result: List[Recipe] = []
        for raw in raw_list:
            if not isinstance(raw, dict):
                continue
            result_obj = raw.get("result") or {}
            result_id = result_obj.get("id", item_id)
            result_name = self._id_to_name.get(result_id, key)
            result_count = int(result_obj.get("count", 1))
            if "inShape" in raw:
                shape_raw = raw.get("inShape") or []
                shape: List[List[Optional[str]]] = []
                for row in shape_raw:
                    row_names = []
                    for cell in row:
                        if cell is None:
                            row_names.append(None)
                        else:
                            row_names.append(self._id_to_name.get(int(cell)))
                    shape.append(row_names)
                result.append(
                    Recipe(
                        result_name=result_name,
                        result_count=result_count,
                        shaped=True,
                        shape=shape,
                    )
                )
            elif "ingredients" in raw:
                ing_raw = raw.get("ingredients") or []
                ingredients = [
                    self._id_to_name.get(int(cell)) for cell in ing_raw if cell is not None
                ]
                result.append(
                    Recipe(
                        result_name=result_name,
                        result_count=result_count,
                        shaped=False,
                        ingredients=ingredients,
                    )
                )
        return result

    def has_item(self, item_name: str) -> bool:
        self._ensure_loaded()
        return item_name in self._name_to_id


ARMOR_SLOT_SUFFIX = {
    "head": ("helmet", "turtle_helmet"),
    "chest": ("chestplate", "elytra"),
    "legs": ("leggings",),
    "feet": ("boots",),
}

ARMOR_MATERIAL_RANK = [
    ("netherite", 6),
    ("diamond", 5),
    ("iron", 4),
    ("chainmail", 3),
    ("golden", 2),
    ("leather", 1),
    ("turtle", 2),
]

HOTBAR_KEYWORDS = [
    ("sword", 100),
    ("pickaxe", 95),
    ("axe", 85),
    ("shovel", 80),
    ("bow", 70),
    ("crossbow", 70),
    ("shield", 60),
    ("torch", 55),
    ("bread", 50),
    ("beef", 50),
    ("porkchop", 50),
    ("chicken", 50),
    ("mutton", 50),
    ("rabbit", 50),
    ("fish", 50),
    ("apple", 50),
    ("carrot", 50),
    ("potato", 50),
    ("steak", 50),
    ("cobblestone", 40),
    ("stone", 40),
    ("dirt", 35),
    ("planks", 35),
]

FOOD_ITEMS = {
    "apple",
    "bread",
    "carrot",
    "potato",
    "baked_potato",
    "beetroot",
    "beetroot_soup",
    "mushroom_stew",
    "rabbit_stew",
    "suspicious_stew",
    "pumpkin_pie",
    "cookie",
    "melon_slice",
    "sweet_berries",
    "glow_berries",
    "chorus_fruit",
    "honey_bottle",
    "golden_apple",
    "enchanted_golden_apple",
    "golden_carrot",
    "raw_beef",
    "cooked_beef",
    "raw_porkchop",
    "cooked_porkchop",
    "raw_chicken",
    "cooked_chicken",
    "raw_mutton",
    "cooked_mutton",
    "raw_rabbit",
    "cooked_rabbit",
    "raw_cod",
    "cooked_cod",
    "raw_salmon",
    "cooked_salmon",
    "tropical_fish",
    "dried_kelp",
}

LOOPING_ITEMS = {
    "coal",
    "wheat",
    "bone_meal",
    "diamond",
    "emerald",
    "raw_iron",
    "raw_gold",
    "redstone",
    "blue_wool",
    "packed_mud",
    "raw_copper",
    "iron_ingot",
    "dried_kelp",
    "gold_ingot",
    "slime_ball",
    "black_wool",
    "quartz_slab",
    "copper_ingot",
    "lapis_lazuli",
    "honey_bottle",
    "rib_armor_trim_smithing_template",
    "eye_armor_trim_smithing_template",
    "vex_armor_trim_smithing_template",
    "dune_armor_trim_smithing_template",
    "host_armor_trim_smithing_template",
    "tide_armor_trim_smithing_template",
    "wild_armor_trim_smithing_template",
    "ward_armor_trim_smithing_template",
    "coast_armor_trim_smithing_template",
    "spire_armor_trim_smithing_template",
    "snout_armor_trim_smithing_template",
    "shaper_armor_trim_smithing_template",
    "netherite_upgrade_smithing_template",
    "raiser_armor_trim_smithing_template",
    "sentry_armor_trim_smithing_template",
    "silence_armor_trim_smithing_template",
    "wayfinder_armor_trim_smithing_template",
}


def _infer_armor_slot(item_name: str) -> Optional[str]:
    for slot, suffixes in ARMOR_SLOT_SUFFIX.items():
        for suffix in suffixes:
            if item_name.endswith(suffix):
                return slot
    return None


def _armor_score(item_name: str) -> int:
    for material, score in ARMOR_MATERIAL_RANK:
        if item_name.startswith(f"{material}_"):
            return score
    if item_name == "elytra":
        return 0
    return 0


def _hotbar_score(item_name: str) -> int:
    for keyword, score in HOTBAR_KEYWORDS:
        if keyword in item_name:
            return score
    return 0


class HeadfulInventoryController:
    def __init__(
        self,
        logger,
        log_append: Callable[[str], None],
        adapter,
        config_provider: Callable[[], Dict[str, Any]],
        data_root: Optional[Path] = None,
    ) -> None:
        self._logger = logger
        self._log_append = log_append
        self._adapter = adapter
        self._config_provider = config_provider
        self._lock = asyncio.Lock()
        self._recipe_book: Optional[RecipeBook] = None
        self._data_root = data_root
        self._llm = LLMService()
        self._memory = MemorySystemService()
        self.last_plan: Optional[Dict[str, Any]] = None
        self._person_service = PersonService()
        self._mindcraft_docs_user_id = "mindcraft_docs"
        self._mindcraft_docs_indexed: set[str] = set()

    def _get_recipe_book(self) -> RecipeBook:
        if self._recipe_book is not None:
            return self._recipe_book
        if self._data_root is None:
            cfg = self._config_provider() or {}
            version = cfg.get("minecraft_version") or "1.21.6"
            if version == "auto":
                version = "1.21.6"
            base = Path(__file__).resolve().parent
            data_root = (
                base
                / "src"
                / "node_modules"
                / "minecraft-data"
                / "minecraft-data"
                / "data"
                / "pc"
                / version
            )
            if not data_root.exists():
                data_root = (
                    base
                    / "src"
                    / "node_modules"
                    / "minecraft-data"
                    / "minecraft-data"
                    / "data"
                    / "pc"
                    / "1.21.6"
                )
            self._data_root = data_root
        self._recipe_book = RecipeBook(self._data_root)
        return self._recipe_book

    def _config(self) -> Dict[str, Any]:
        cfg = self._config_provider() or {}
        return cfg if isinstance(cfg, dict) else {}

    def _headful_config(self) -> Dict[str, Any]:
        cfg = self._config()
        return cfg.get("headful", cfg)

    async def run(self, skill: str, params: Dict[str, Any]) -> Dict[str, Any]:
        async with self._lock:
            name = (skill or "").strip().lower()
            if name in {"auto_equip", "equip"}:
                return await self.auto_equip()
            if name in {"auto_sort", "auto_sort_hotbar", "sort_hotbar"}:
                return await self.auto_sort_hotbar()
            if name in {"container_transfer", "transfer"}:
                return await self.container_transfer(params)
            if name in {"craft", "auto_craft"}:
                return await self.craft_item(params)
            if name in {"plan", "plan_only", "planner"}:
                return await self.plan_actions(params, execute=False)
            if name in {"plan_execute", "plan_and_execute", "planrun"}:
                return await self.plan_actions(params, execute=True)
            if name in {"screen_snapshot", "snapshot"}:
                snap = await self._get_snapshot(refresh=True)
                return {"ok": bool(snap), "snapshot": snap}
            return {"ok": False, "error": "unknown_skill"}

    async def _get_snapshot(self, refresh: bool = True) -> Optional[Dict[str, Any]]:
        config = self._headful_config()
        if refresh:
            snap = await self._adapter.request_screen_snapshot(config)
            if isinstance(snap, dict):
                if "slots" in snap:
                    return snap
                if self._adapter.last_screen:
                    return self._adapter.last_screen
            return snap or self._adapter.last_screen
        return self._adapter.last_screen

    async def _send_sequence(self, actions: List[Dict[str, Any]]) -> bool:
        if not actions:
            return True
        payload = {"type": "runSequence", "actions": actions}
        return await self._adapter.send_action(payload, self._headful_config())

    def _build_counts(self, slots: Iterable[SlotInfo], groups: Tuple[str, ...]) -> Dict[str, int]:
        counts: Dict[str, int] = {}
        for slot in slots:
            if slot.group not in groups or slot.item is None:
                continue
            counts[slot.item.name] = counts.get(slot.item.name, 0) + slot.item.count
        return counts

    def _slots_by_group(self, slots: Iterable[SlotInfo], groups: Tuple[str, ...]) -> List[SlotInfo]:
        return [slot for slot in slots if slot.group in groups]

    def _actions_move_one(self, source_slot: int, target_slot: int) -> List[Dict[str, Any]]:
        return [
            {"type": "clickSlot", "slot": source_slot, "button": 0, "action": "pickup"},
            {"type": "clickSlot", "slot": target_slot, "button": 1, "action": "pickup"},
            {"type": "clickSlot", "slot": source_slot, "button": 0, "action": "pickup"},
        ]

    def _chunk_text(self, text: str, max_len: int = 800, overlap: int = 80) -> List[str]:
        cleaned = (text or "").replace("\r\n", "\n").strip()
        if not cleaned:
            return []
        paragraphs = [p.strip() for p in cleaned.split("\n\n") if p.strip()]
        chunks: List[str] = []
        buf = ""
        for para in paragraphs:
            if not buf:
                buf = para
                continue
            if len(buf) + 2 + len(para) <= max_len:
                buf = f"{buf}\n\n{para}"
            else:
                chunks.append(buf)
                if overlap > 0 and len(buf) > overlap:
                    buf = f"{buf[-overlap:]}\n\n{para}"
                else:
                    buf = para
        if buf:
            chunks.append(buf)

        final: List[str] = []
        for chunk in chunks:
            if len(chunk) <= max_len * 1.2:
                final.append(chunk)
                continue
            start = 0
            step = max_len - overlap if overlap > 0 else max_len
            while start < len(chunk):
                final.append(chunk[start : start + max_len])
                start += step
        return final

    def _read_mindcraft_docs(self) -> List[Tuple[str, str]]:
        base = Path(__file__).resolve().parent / "src"
        docs = [
            ("README.md", base / "README.md"),
            ("FAQ.md", base / "FAQ.md"),
        ]
        results: List[Tuple[str, str]] = []
        for name, path in docs:
            if path.exists():
                try:
                    content = path.read_text(encoding="utf-8")
                    results.append((name, content))
                except Exception:
                    continue
        return results

    async def _ensure_mindcraft_docs_indexed(self, user_id: str) -> None:
        if not user_id:
            return
        if user_id in self._mindcraft_docs_indexed:
            return
        with Session(engine) as session:
            statement = (
                select(MemoryPoint)
                .join(Person)
                .where(Person.user_id == user_id, MemoryPoint.category == "mindcraft_doc")
                .limit(1)
            )
            existing = session.exec(statement).first()
        if existing:
            self._mindcraft_docs_indexed.add(user_id)
            return

        docs = self._read_mindcraft_docs()
        if not docs:
            return
        total_chunks = 0
        max_chunks = 40
        for filename, content in docs:
            for chunk in self._chunk_text(content):
                if total_chunks >= max_chunks:
                    break
                payload = f"[MindcraftDoc:{filename}]\n{chunk}"
                await self._person_service.add_memory_point(
                    user_id=user_id,
                    content=payload,
                    category="mindcraft_doc",
                    weight=0.4,
                )
                total_chunks += 1
            if total_chunks >= max_chunks:
                break
        self._mindcraft_docs_indexed.add(user_id)

    def _snapshot_for_planner(self, snapshot: ScreenSnapshot) -> Dict[str, Any]:
        slots = []
        for slot in snapshot.slots:
            item = None
            if slot.item is not None:
                item = {
                    "id": slot.item.item_id,
                    "name": slot.item.name,
                    "count": slot.item.count,
                    "max": slot.item.max_count,
                }
            slots.append(
                {
                    "slot": slot.slot,
                    "group": slot.group,
                    "x": slot.x,
                    "y": slot.y,
                    "equip": slot.equip,
                    "item": item,
                }
            )
        cursor = None
        if snapshot.cursor is not None:
            cursor = {
                "id": snapshot.cursor.item_id,
                "name": snapshot.cursor.name,
                "count": snapshot.cursor.count,
                "max": snapshot.cursor.max_count,
            }
        crafting_grid = None
        grid_info = self._crafting_grid(snapshot.slots)
        if grid_info is not None:
            grid, width, height = grid_info
            grid_slots = []
            for (gx, gy), slot in grid.items():
                grid_slots.append({"slot": slot.slot, "x": gx, "y": gy})
            output_slot = next(
                (slot for slot in snapshot.slots if slot.group == "crafting_output"),
                None,
            )
            crafting_grid = {
                "width": width,
                "height": height,
                "slots": grid_slots,
                "output_slot": output_slot.slot if output_slot else None,
            }
        return {
            "handler": snapshot.handler,
            "screen_open": snapshot.screen_open,
            "title": snapshot.title,
            "cursor": cursor,
            "slots": slots,
            "crafting_grid": crafting_grid,
        }

    def _extract_json_object(self, text: str) -> Optional[Dict[str, Any]]:
        if not text:
            return None
        raw = text.strip()
        fence_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", raw, re.S)
        if fence_match:
            raw = fence_match.group(1)
        start = raw.find("{")
        end = raw.rfind("}")
        if start == -1 or end == -1 or end <= start:
            return None
        raw = raw[start : end + 1]
        try:
            parsed = json.loads(raw)
        except Exception:
            return None
        if isinstance(parsed, dict):
            return parsed
        return None

    def _normalize_action_type(self, raw_type: str) -> Optional[str]:
        if not raw_type:
            return None
        key = raw_type.strip().lower().replace("_", "")
        mapping = {
            "openinventory": "openInventory",
            "openscreen": "openInventory",
            "closescreen": "closeScreen",
            "screensnapshot": "screenSnapshot",
            "snapshot": "screenSnapshot",
            "quickmove": "quickMove",
            "movestack": "moveStack",
            "moveone": "moveOne",
            "equip": "equip",
            "clickslot": "clickSlot",
            "wait": "wait",
            "hotbar": "hotbar",
            "tapkey": "tapKey",
            "setkey": "setKey",
            "releaseallkeys": "releaseAllKeys",
            "chat": "chat",
            "command": "command",
        }
        return mapping.get(key)

    def _validate_plan_actions(
        self, actions: List[Dict[str, Any]], slot_ids: set[int]
    ) -> Tuple[List[Dict[str, Any]], List[str]]:
        valid: List[Dict[str, Any]] = []
        warnings: List[str] = []
        for idx, action in enumerate(actions):
            if not isinstance(action, dict):
                warnings.append(f"step {idx}: not an object")
                continue
            raw_type = action.get("type")
            norm_type = self._normalize_action_type(str(raw_type or ""))
            if not norm_type:
                warnings.append(f"step {idx}: unsupported type {raw_type}")
                continue
            action["type"] = norm_type
            if norm_type in {"openInventory", "closeScreen", "screenSnapshot", "releaseAllKeys"}:
                valid.append(action)
                continue
            if norm_type == "wait":
                ms = action.get("ms")
                if isinstance(ms, (int, float)) and ms > 0:
                    action["ms"] = int(ms)
                    valid.append(action)
                else:
                    warnings.append(f"step {idx}: wait missing ms")
                continue
            if norm_type == "hotbar":
                slot = action.get("slot")
                if isinstance(slot, int) and 0 <= slot <= 8:
                    valid.append(action)
                else:
                    warnings.append(f"step {idx}: hotbar slot invalid")
                continue
            if norm_type == "tapKey":
                key = action.get("key")
                if isinstance(key, str) and key:
                    action["durationMs"] = int(action.get("durationMs", 120))
                    valid.append(action)
                else:
                    warnings.append(f"step {idx}: tapKey missing key")
                continue
            if norm_type == "setKey":
                key = action.get("key")
                pressed = action.get("pressed")
                if isinstance(key, str) and isinstance(pressed, bool):
                    valid.append(action)
                else:
                    warnings.append(f"step {idx}: setKey missing key/pressed")
                continue
            if norm_type in {"chat", "command"}:
                message = action.get("message") if norm_type == "chat" else action.get("command")
                if isinstance(message, str) and message:
                    valid.append(action)
                else:
                    warnings.append(f"step {idx}: {norm_type} missing message")
                continue
            if norm_type == "quickMove":
                slot = action.get("slot")
                if isinstance(slot, int) and slot in slot_ids:
                    valid.append(action)
                else:
                    warnings.append(f"step {idx}: quickMove invalid slot")
                continue
            if norm_type == "moveStack":
                src = action.get("fromSlot")
                dst = action.get("toSlot")
                if isinstance(src, int) and isinstance(dst, int) and src in slot_ids and dst in slot_ids:
                    valid.append(action)
                else:
                    warnings.append(f"step {idx}: moveStack invalid slots")
                continue
            if norm_type == "moveOne":
                src = action.get("fromSlot")
                dst = action.get("toSlot")
                if isinstance(src, int) and isinstance(dst, int) and src in slot_ids and dst in slot_ids:
                    valid.append(action)
                else:
                    warnings.append(f"step {idx}: moveOne invalid slots")
                continue
            if norm_type == "equip":
                src = action.get("sourceSlot")
                target = action.get("target")
                if isinstance(src, int) and src in slot_ids and isinstance(target, str) and target:
                    valid.append(action)
                else:
                    warnings.append(f"step {idx}: equip invalid")
                continue
            if norm_type == "clickSlot":
                slot = action.get("slot")
                button = action.get("button", 0)
                act = action.get("action")
                if (
                    isinstance(slot, int)
                    and slot in slot_ids
                    and isinstance(button, int)
                    and isinstance(act, str)
                ):
                    valid.append(action)
                else:
                    warnings.append(f"step {idx}: clickSlot invalid")
                continue
        return valid, warnings

    async def _execute_plan_actions(
        self,
        actions: List[Dict[str, Any]],
        step_delay_ms: int,
        refresh_snapshot: bool,
    ) -> int:
        executed = 0
        for action in actions:
            action_type = action.get("type")
            if action_type == "wait":
                await asyncio.sleep(max(0, int(action.get("ms", 50))) / 1000)
                executed += 1
                continue
            if action_type == "screenSnapshot":
                await self._get_snapshot(refresh=True)
                executed += 1
                continue
            if action_type == "moveOne":
                seq = self._actions_move_one(
                    int(action["fromSlot"]), int(action["toSlot"])
                )
                await self._send_sequence(seq)
                executed += 1
            elif action_type == "moveStack":
                await self._adapter.send_action(
                    {
                        "type": "moveStack",
                        "fromSlot": int(action["fromSlot"]),
                        "toSlot": int(action["toSlot"]),
                        "button": int(action.get("button", 0)),
                    },
                    self._headful_config(),
                )
                executed += 1
            elif action_type == "quickMove":
                await self._adapter.send_action(
                    {"type": "quickMove", "slot": int(action["slot"])},
                    self._headful_config(),
                )
                executed += 1
            elif action_type == "equip":
                await self._adapter.send_action(
                    {
                        "type": "equip",
                        "sourceSlot": int(action["sourceSlot"]),
                        "target": action["target"],
                    },
                    self._headful_config(),
                )
                executed += 1
            elif action_type == "clickSlot":
                await self._adapter.send_action(
                    {
                        "type": "clickSlot",
                        "slot": int(action["slot"]),
                        "button": int(action.get("button", 0)),
                        "action": action.get("action", "pickup"),
                    },
                    self._headful_config(),
                )
                executed += 1
            elif action_type in {"openInventory", "closeScreen", "tapKey", "setKey", "releaseAllKeys", "hotbar", "chat", "command"}:
                await self._adapter.send_action(action, self._headful_config())
                executed += 1
            if step_delay_ms > 0:
                await asyncio.sleep(step_delay_ms / 1000)
            if refresh_snapshot:
                await self._get_snapshot(refresh=True)
        return executed

    async def _run_llm_plan(
        self,
        goal: str,
        snapshot: ScreenSnapshot,
        params: Dict[str, Any],
    ) -> Dict[str, Any]:
        cfg = self._config()
        api_key = cfg.get("agent_api_key")
        base_url = cfg.get("agent_base_url")
        model = cfg.get("agent_model")
        user_id = (
            params.get("rag_user_id")
            or cfg.get("rag_user_id")
            or cfg.get("agent_name")
            or "minecraft"
        )
        use_rag = bool(params.get("use_rag", True))
        use_mindcraft_docs = bool(params.get("use_mindcraft_docs", False))
        if use_rag and use_mindcraft_docs:
            try:
                await self._ensure_mindcraft_docs_indexed(str(user_id))
            except Exception:
                pass
        rag_context = ""
        if use_rag:
            try:
                rag_context = await self._memory.retrieve_context(
                    user_query=goal,
                    user_id=str(user_id),
                    api_key=api_key,
                    base_url=base_url,
                    model=None,
                    fast_mode=True,
                )
            except Exception:
                rag_context = ""

        system_prompt = (
            "You are a Minecraft GUI action planner. "
            "Output JSON only with the schema: {\"actions\":[...],\"reason\":\"\"}. "
            "Use only allowed actions. If unsure, return empty actions with a reason."
        )
        actions_spec = {
            "openInventory": {},
            "closeScreen": {},
            "screenSnapshot": {},
            "wait": {"ms": 150},
            "moveStack": {"fromSlot": 0, "toSlot": 0},
            "moveOne": {"fromSlot": 0, "toSlot": 0},
            "quickMove": {"slot": 0},
            "equip": {"sourceSlot": 0, "target": "head|chest|legs|feet|offhand"},
            "clickSlot": {"slot": 0, "button": 0, "action": "pickup|quick_move|swap|throw|clone|pickup_all"},
            "hotbar": {"slot": 0},
            "tapKey": {"key": "use|attack|drop|swap", "durationMs": 120},
            "setKey": {"key": "forward|back|left|right|sprint|sneak|attack|use", "pressed": True},
            "releaseAllKeys": {},
            "chat": {"message": "text"},
            "command": {"command": "time set day"},
        }
        snapshot_payload = self._snapshot_for_planner(snapshot)
        user_payload = {
            "goal": goal,
            "screen": snapshot_payload,
            "allowed_actions": actions_spec,
            "rag_context": rag_context[:4000],
            "notes": [
                "Use slot indices from the snapshot only.",
                "For crafting, place items into crafting_input slots.",
                "Use screen.crafting_grid if provided to know the grid width/height.",
                "Crafting table (minecraft:crafting_table) uses a 2x2 grid of any planks and can be crafted in the player inventory.",
                "Logs can be crafted into planks (1 log -> 4 planks) in any grid.",
                "Use moveOne to place a single item, moveStack for full stacks.",
                "If cursor holds an item, place it into an empty player slot first.",
                "In creative inventory, use clickSlot with action=clone to copy items from the creative list.",
                "Equip armor via equip {sourceSlot,target} where target is head/chest/legs/feet/offhand.",
            ],
        }

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": json.dumps(user_payload, ensure_ascii=False)},
        ]
        try:
            response = await self._llm.get_response(
                messages=messages,
                api_key=api_key,
                base_url=base_url,
                model=model,
                temperature=float(params.get("temperature", 0.2)),
                timeout=float(params.get("timeout", 60.0)),
            )
        except Exception as exc:
            return {"ok": False, "error": f"llm_error: {exc}", "actions": [], "planner": "llm"}

        plan = self._extract_json_object(response)
        if not plan:
            return {"ok": False, "error": "plan_parse_failed", "actions": [], "planner": "llm"}
        raw_actions = plan.get("actions")
        if not isinstance(raw_actions, list):
            return {"ok": False, "error": "plan_missing_actions", "actions": [], "planner": "llm"}
        slot_ids = {slot.slot for slot in snapshot.slots}
        actions, warnings = self._validate_plan_actions(raw_actions, slot_ids)
        reason = plan.get("reason") if isinstance(plan.get("reason"), str) else None
        return {
            "ok": True,
            "actions": actions,
            "reason": reason,
            "warnings": warnings,
            "planner": "llm",
        }

    async def plan_actions(self, params: Dict[str, Any], execute: bool = False) -> Dict[str, Any]:
        goal = (params.get("goal") or "").strip()
        if not goal:
            return {"ok": False, "error": "missing_goal"}
        raw = await self._get_snapshot(refresh=True)
        if isinstance(raw, dict) and raw.get("status") and "slots" not in raw:
            status = str(raw.get("status"))
            self._log_append(f"Headful snapshot unavailable: {status}")
            return {"ok": False, "error": "snapshot_unavailable", "status": status}
        snapshot = ScreenSnapshot.from_dict(raw)
        if snapshot is None:
            return {"ok": False, "error": "no_snapshot"}
        available = self._build_counts(snapshot.slots, ("player_main", "player_hotbar"))
        plan_trace: List[Dict[str, Any]] = []
        selected: Optional[Dict[str, Any]] = None
        fallback_plan: Optional[Dict[str, Any]] = None

        rule_plan = await self._plan_from_rules(goal, snapshot, available)
        if rule_plan:
            actions = rule_plan.get("actions")
            actions_list = actions if isinstance(actions, list) else []
            reason = rule_plan.get("reason")
            plan_trace.append(
                {
                    "planner": rule_plan.get("planner"),
                    "ok": rule_plan.get("ok"),
                    "actions": len(actions_list),
                    "reason": reason,
                }
            )
            if actions_list:
                selected = rule_plan
            elif isinstance(reason, str) and (
                reason.startswith("already_equipped")
                or reason.startswith("no_matching_armor")
            ):
                selected = rule_plan
            else:
                fallback_plan = rule_plan

        llm_plan = None
        if selected is None:
            llm_plan = await self._run_llm_plan(goal, snapshot, params)
            llm_actions = llm_plan.get("actions") if isinstance(llm_plan, dict) else []
            llm_actions_list = llm_actions if isinstance(llm_actions, list) else []
            plan_trace.append(
                {
                    "planner": llm_plan.get("planner"),
                    "ok": llm_plan.get("ok"),
                    "actions": len(llm_actions_list),
                    "reason": llm_plan.get("reason"),
                    "error": llm_plan.get("error"),
                }
            )
            if llm_plan.get("ok") and llm_actions_list:
                selected = llm_plan
            elif fallback_plan is None and llm_plan.get("plan_text"):
                fallback_plan = llm_plan

        if selected is None:
            text_plan = self._plan_text_only(goal, available)
            if text_plan:
                plan_trace.append(
                    {
                        "planner": text_plan.get("planner"),
                        "ok": text_plan.get("ok"),
                        "actions": 0,
                        "reason": text_plan.get("reason"),
                    }
                )
                if fallback_plan is None:
                    fallback_plan = text_plan

        if selected is None:
            selected = fallback_plan or {
                "ok": True,
                "actions": [],
                "reason": "no_plan",
                "warnings": [],
                "planner": "none",
                "plan_text": None,
            }

        actions = selected.get("actions") if isinstance(selected, dict) else []
        actions_list = actions if isinstance(actions, list) else []
        warnings = selected.get("warnings") if isinstance(selected, dict) else []
        warnings_list = warnings if isinstance(warnings, list) else []
        reason = selected.get("reason") if isinstance(selected, dict) else None
        planner = selected.get("planner") if isinstance(selected, dict) else None
        plan_text = selected.get("plan_text") if isinstance(selected, dict) else None

        plan_payload: Dict[str, Any] = {
            "goal": goal,
            "actions": actions_list,
            "reason": reason,
            "warnings": warnings_list,
            "planner": planner,
            "plan_text": plan_text,
            "trace": plan_trace,
            "timestamp": time.time(),
        }
        self.last_plan = plan_payload

        if warnings_list:
            self._log_append("Headful planner warnings: " + "; ".join(warnings_list[:6]))
        for idx, action in enumerate(actions_list[:20]):
            self._log_append(f"Plan step {idx + 1}: {action}")
        if len(actions_list) > 20:
            self._log_append(f"Plan steps truncated: {len(actions_list)} total.")

        if not execute:
            self._log_append(f"Headful planner ready: {len(actions_list)} steps.")
            return {
                "ok": True,
                "actions": actions_list,
                "reason": reason,
                "warnings": warnings_list,
                "planner": planner,
                "plan_text": plan_text,
                "trace": plan_trace,
            }

        step_delay_ms = int(params.get("step_delay_ms", 120))
        refresh_snapshot = bool(params.get("refresh_snapshot", False))
        executed = 0
        if actions_list:
            executed = await self._execute_plan_actions(
                actions_list, step_delay_ms, refresh_snapshot
            )
            self._log_append(f"Headful planner executed: {executed}/{len(actions_list)} steps.")

        auto_substeps = None
        auto_error = None
        if not actions_list and self._goal_is_crafting_table(goal):
            auto_result = await self._auto_craft_table(params)
            auto_substeps = auto_result.get("substeps") if isinstance(auto_result, dict) else None
            auto_error = auto_result.get("error") if isinstance(auto_result, dict) else None
            if auto_substeps is not None:
                plan_payload["auto_substeps"] = auto_substeps
            if auto_error:
                plan_payload["auto_error"] = auto_error
            self.last_plan = plan_payload
            if auto_result.get("ok"):
                return {
                    "ok": True,
                    "actions": actions_list,
                    "executed": executed,
                    "reason": reason,
                    "warnings": warnings_list,
                    "planner": planner,
                    "plan_text": plan_text,
                    "trace": plan_trace,
                    "auto_substeps": auto_substeps,
                }

        if self.last_plan:
            self.last_plan["executed"] = executed
            self.last_plan["executed_at"] = time.time()
        return {
            "ok": True,
            "actions": actions_list,
            "executed": executed,
            "reason": reason,
            "warnings": warnings_list,
            "planner": planner,
            "plan_text": plan_text,
            "trace": plan_trace,
            "auto_substeps": auto_substeps,
            "auto_error": auto_error,
        }

    async def _auto_craft_table(self, params: Dict[str, Any]) -> Dict[str, Any]:
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        if snapshot is None:
            return {"ok": False, "error": "no_snapshot"}
        grid_info = self._crafting_grid(snapshot.slots)
        if not grid_info:
            await self._adapter.send_action({"type": "openInventory"}, self._headful_config())
            await asyncio.sleep(0.2)
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot is None:
                return {"ok": False, "error": "no_snapshot"}
            grid_info = self._crafting_grid(snapshot.slots)
        if not grid_info:
            return {"ok": False, "error": "no_crafting_grid"}

        available = self._build_counts(snapshot.slots, ("player_main", "player_hotbar"))
        plank_count = sum(
            count for name, count in available.items() if self._is_planks(name)
        )
        substeps: List[Dict[str, Any]] = []
        if plank_count < 4:
            log_name = next((name for name in available if self._is_log(name)), None)
            plank_name = self._log_to_planks(log_name or "")
            if not log_name or not plank_name:
                return {
                    "ok": False,
                    "error": "missing_items",
                    "missing": {"planks": max(0, 4 - plank_count)},
                }
            planks_result = await self.craft_item(
                {"item": plank_name, "count": 4, "max_times": 1},
                execute=True,
            )
            substeps.append({"step": "craft_planks", "result": planks_result})
            if not planks_result.get("ok"):
                return {
                    "ok": False,
                    "error": "craft_planks_failed",
                    "detail": planks_result,
                }

        table_result = await self.craft_item(
            {"item": "crafting_table", "count": 1},
            execute=True,
        )
        substeps.append({"step": "craft_table", "result": table_result})
        if not table_result.get("ok"):
            return {
                "ok": False,
                "error": "craft_table_failed",
                "detail": table_result,
            }
        return {
            "ok": True,
            "substeps": substeps,
        }

    async def auto_equip(self) -> Dict[str, Any]:
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        if snapshot is None:
            return {"ok": False, "error": "no_snapshot"}
        planned = self._plan_equip_actions(snapshot, goal="", allow_shield=True)
        actions = planned.get("actions") if isinstance(planned, dict) else []
        equipped = planned.get("equipped") if isinstance(planned, dict) else {}
        ok = await self._send_sequence(actions)
        return {
            "ok": ok,
            "actions": len(actions),
            "equipped": equipped,
        }

    async def auto_sort_hotbar(self) -> Dict[str, Any]:
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        if snapshot is None:
            return {"ok": False, "error": "no_snapshot"}
        hotbar = [slot for slot in snapshot.slots if slot.group == "player_hotbar"]
        empty_hotbar = [slot for slot in hotbar if slot.item is None]
        if not empty_hotbar:
            return {"ok": True, "actions": 0, "message": "no_empty_hotbar"}
        inventory = [
            slot
            for slot in snapshot.slots
            if slot.group == "player_main" and slot.item is not None
        ]
        scored = sorted(
            inventory,
            key=lambda slot: _hotbar_score(slot.item.name),
            reverse=True,
        )
        actions: List[Dict[str, Any]] = []
        used_slots = set()
        moved = 0
        for target in empty_hotbar:
            source = next(
                (
                    slot
                    for slot in scored
                    if slot.slot not in used_slots and _hotbar_score(slot.item.name) > 0
                ),
                None,
            )
            if source is None:
                break
            actions.append(
                {"type": "moveStack", "fromSlot": source.slot, "toSlot": target.slot}
            )
            used_slots.add(source.slot)
            moved += 1
        ok = await self._send_sequence(actions)
        return {"ok": ok, "actions": len(actions), "moved": moved}

    async def container_transfer(self, params: Dict[str, Any]) -> Dict[str, Any]:
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        if snapshot is None:
            return {"ok": False, "error": "no_snapshot"}
        direction = (params.get("direction") or "to_inventory").lower()
        item_filter = _normalize_item_name(params.get("item"))
        max_slots = int(params.get("max_slots", 54))
        if direction == "to_container":
            source_groups = ("player_main", "player_hotbar")
        else:
            source_groups = (
                "container",
                "container_input",
                "container_fuel",
                "container_output",
            )
        slots = [
            slot
            for slot in snapshot.slots
            if slot.group in source_groups and slot.item is not None
        ]
        if item_filter:
            slots = [slot for slot in slots if slot.item and slot.item.name == item_filter]
        actions = [
            {"type": "quickMove", "slot": slot.slot} for slot in slots[:max_slots]
        ]
        ok = await self._send_sequence(actions)
        return {"ok": ok, "actions": len(actions), "direction": direction}

    def _crafting_grid(self, slots: List[SlotInfo]) -> Optional[Tuple[Dict[Tuple[int, int], SlotInfo], int, int]]:
        craft_slots = [slot for slot in slots if slot.group == "crafting_input"]
        if not craft_slots:
            return None
        xs = sorted({slot.x for slot in craft_slots})
        ys = sorted({slot.y for slot in craft_slots})
        grid: Dict[Tuple[int, int], SlotInfo] = {}
        for slot in craft_slots:
            grid[(xs.index(slot.x), ys.index(slot.y))] = slot
        return grid, len(xs), len(ys)

    def _recipe_requirements(self, recipe: Recipe) -> Dict[str, int]:
        counts: Dict[str, int] = {}
        if recipe.shaped and recipe.shape:
            for row in recipe.shape:
                for cell in row:
                    if cell:
                        counts[cell] = counts.get(cell, 0) + 1
        elif recipe.ingredients:
            for cell in recipe.ingredients:
                if cell:
                    counts[cell] = counts.get(cell, 0) + 1
        return counts

    def _max_craftable(self, recipe: Recipe, available: Dict[str, int]) -> int:
        requirements = self._recipe_requirements(recipe)
        if not requirements:
            return 0
        return min(available.get(item, 0) // count for item, count in requirements.items())

    def _recipe_fits(self, recipe: Recipe, width: int, height: int) -> bool:
        if recipe.shaped and recipe.shape:
            rh = len(recipe.shape)
            rw = max((len(row) for row in recipe.shape), default=0)
            return rh <= height and rw <= width
        if recipe.ingredients:
            return len(recipe.ingredients) <= width * height
        return False

    def _goal_is_crafting_table(self, goal: str) -> bool:
        lowered = (goal or "").lower()
        return "工作台" in goal or "crafting_table" in lowered or "crafting table" in lowered or "workbench" in lowered

    def _goal_is_craft(self, goal: str) -> bool:
        lowered = (goal or "").lower()
        return any(keyword in lowered for keyword in ("craft", "make", "build", "create")) or "合成" in goal or "制作" in goal or "打造" in goal

    def _goal_is_eat(self, goal: str) -> bool:
        lowered = (goal or "").lower()
        if any(keyword in lowered for keyword in ("eat", "food", "hunger", "fill")):
            return True
        return any(
            keyword in goal
            for keyword in (
                "吃",
                "进食",
                "吃东西",
                "吃点",
                "吃点东西",
                "饿",
                "饥饿",
                "补充饥饿",
                "饱食度",
                "吃饱",
                "回满",
                "补满",
            )
        )

    def _goal_is_equip(self, goal: str) -> bool:
        lowered = (goal or "").lower()
        if "装备" in goal or "穿上" in goal or "穿戴" in goal:
            return True
        return any(keyword in lowered for keyword in ("equip", "wear", "put on"))

    def _goal_armor_material(self, goal: str) -> Optional[str]:
        lowered = (goal or "").lower()
        if "下界合金" in goal or "netherite" in lowered:
            return "netherite"
        if "钻石" in goal or "diamond" in lowered:
            return "diamond"
        if "铁" in goal or "iron" in lowered:
            return "iron"
        if "锁链" in goal or "chainmail" in lowered or "chain" in lowered:
            return "chainmail"
        if "皮革" in goal or "皮" in goal or "leather" in lowered:
            return "leather"
        if "海龟" in goal or "turtle" in lowered:
            return "turtle"
        if "金" in goal or "gold" in lowered or "golden" in lowered:
            return "golden"
        return None

    def _matches_armor_material(self, item_name: str, material: Optional[str]) -> bool:
        if not material:
            return True
        if material == "golden":
            return item_name.startswith("golden_")
        return item_name.startswith(f"{material}_")

    def _is_food_item(self, item_name: str) -> bool:
        if item_name in FOOD_ITEMS:
            return True
        if item_name.endswith("_stew") or item_name.endswith("_soup"):
            return True
        return False

    def _hotbar_index_for_slot(
        self, snapshot: ScreenSnapshot, slot: SlotInfo
    ) -> Optional[int]:
        if 0 <= slot.inv_index <= 8:
            return slot.inv_index
        hotbar = [s for s in snapshot.slots if s.group == "player_hotbar"]
        hotbar.sort(key=lambda s: (s.y, s.x, s.slot))
        for idx, item in enumerate(hotbar):
            if item.slot == slot.slot:
                return idx
        return None

    def _plan_eat_actions(self, snapshot: ScreenSnapshot, goal: str) -> Dict[str, Any]:
        goal_hint = goal or ""
        lowered = goal_hint.lower()
        eat_duration_ms = 1800
        if any(
            keyword in goal_hint
            for keyword in ("吃饱", "回满", "补满", "饱食度", "满饥饿", "回满饱食度")
        ) or any(keyword in lowered for keyword in ("fill", "full")):
            eat_duration_ms = 6000
        hotbar_slots = [
            slot
            for slot in snapshot.slots
            if slot.group == "player_hotbar"
            and slot.item is not None
            and self._is_food_item(slot.item.name)
        ]
        main_slots = [
            slot
            for slot in snapshot.slots
            if slot.group == "player_main"
            and slot.item is not None
            and self._is_food_item(slot.item.name)
        ]
        actions: List[Dict[str, Any]] = []
        if hotbar_slots:
            hotbar_slots.sort(key=lambda s: s.item.count if s.item else 0, reverse=True)
            chosen = hotbar_slots[0]
            hotbar_index = self._hotbar_index_for_slot(snapshot, chosen)
            if hotbar_index is None:
                return {
                    "ok": True,
                    "actions": [],
                    "reason": "no_hotbar_index",
                    "planner": "rules:eat",
                    "plan_text": "无法识别热键栏索引，请手动切换食物。",
                    "warnings": [],
                }
            actions.append({"type": "hotbar", "slot": hotbar_index})
            actions.append({"type": "tapKey", "key": "use", "durationMs": eat_duration_ms})
            return {
                "ok": True,
                "actions": actions,
                "reason": "eat_from_hotbar",
                "planner": "rules:eat",
                "plan_text": None,
                "warnings": [],
            }
        if main_slots:
            main_slots.sort(key=lambda s: s.item.count if s.item else 0, reverse=True)
            chosen = main_slots[0]
            hotbar_targets = [s for s in snapshot.slots if s.group == "player_hotbar"]
            hotbar_targets.sort(key=lambda s: (s.item is not None, s.x, s.y, s.slot))
            target = next((s for s in hotbar_targets if s.item is None), None) or hotbar_targets[0]
            actions.append({"type": "moveStack", "fromSlot": chosen.slot, "toSlot": target.slot})
            hotbar_index = self._hotbar_index_for_slot(snapshot, target)
            if hotbar_index is None:
                return {
                    "ok": True,
                    "actions": actions,
                    "reason": "move_food_no_hotbar_index",
                    "planner": "rules:eat",
                    "plan_text": "已规划移动食物到热键栏，但无法识别索引。",
                    "warnings": [],
                }
            actions.append({"type": "hotbar", "slot": hotbar_index})
            actions.append({"type": "tapKey", "key": "use", "durationMs": eat_duration_ms})
            return {
                "ok": True,
                "actions": actions,
                "reason": "eat_from_inventory",
                "planner": "rules:eat",
                "plan_text": None,
                "warnings": [],
            }
        return {
            "ok": True,
            "actions": [],
            "reason": "no_food",
            "planner": "rules:eat",
            "plan_text": "没有找到可食用物品，请先准备食物。",
            "warnings": [],
        }

    def _extract_item_from_goal(self, goal: str) -> Optional[str]:
        lowered = (goal or "").lower()
        recipe_book = self._get_recipe_book()
        for token in re.findall(r"minecraft:[a-z0-9_]+", lowered):
            name = _normalize_item_name(token)
            if recipe_book.has_item(name):
                return name
        tokens = re.findall(r"[a-z0-9_]+", lowered)
        stopwords = {
            "craft",
            "make",
            "build",
            "create",
            "equip",
            "wear",
            "plan",
            "goal",
            "the",
            "a",
            "an",
            "to",
            "for",
            "with",
            "and",
            "or",
            "on",
            "in",
            "use",
        }
        for token in tokens:
            if token in stopwords:
                continue
            if recipe_book.has_item(token):
                return token
        return None

    def _is_base_item(self, item_name: str) -> bool:
        if item_name in LOOPING_ITEMS:
            return True
        recipe_book = self._get_recipe_book()
        return len(recipe_book.get_recipes(item_name)) == 0

    def _crafting_plan_text(
        self, target_item: str, count: int, available: Dict[str, int]
    ) -> str:
        recipe_book = self._get_recipe_book()
        if not target_item or count <= 0:
            return "Invalid input. Please provide a valid item name and positive count."
        if not recipe_book.has_item(target_item):
            return f"Unknown item: {target_item}"
        if self._is_base_item(target_item):
            have = available.get(target_item, 0)
            if have >= count:
                return "You have all required items already in your inventory!"
            return f"{target_item} is a base item, you need to find {count - have} more in the world"

        inventory = dict(available)
        leftovers: Dict[str, int] = {}
        crafted = {"required": {}, "steps": [], "leftovers": {}}

        def craft_item_plan(item: str, needed: int) -> None:
            available_inv = inventory.get(item, 0)
            available_left = leftovers.get(item, 0)
            total_available = available_inv + available_left
            if total_available >= needed:
                use_from_left = min(available_left, needed)
                leftovers[item] = available_left - use_from_left
                remaining_needed = needed - use_from_left
                if remaining_needed > 0:
                    inventory[item] = available_inv - remaining_needed
                return

            still_needed = needed - total_available
            if available_left > 0:
                leftovers[item] = 0
            if available_inv > 0:
                inventory[item] = 0

            if self._is_base_item(item):
                crafted["required"][item] = crafted["required"].get(item, 0) + still_needed
                return

            recipes = recipe_book.get_recipes(item)
            if not recipes:
                crafted["required"][item] = crafted["required"].get(item, 0) + still_needed
                return
            recipe = recipes[0]
            requirements = self._recipe_requirements(recipe)
            crafted_per = max(recipe.result_count, 1)
            batch_count = int(math.ceil(still_needed / crafted_per))
            total_produced = batch_count * crafted_per

            if total_produced > still_needed:
                leftovers[item] = leftovers.get(item, 0) + (total_produced - still_needed)

            for ingredient_name, ingredient_count in requirements.items():
                craft_item_plan(ingredient_name, ingredient_count * batch_count)

            step_ingredients = " + ".join(
                f"{amount * batch_count} {name}"
                for name, amount in requirements.items()
            )
            crafted["steps"].append(f"Craft {step_ingredients} -> {total_produced} {item}")

        craft_item_plan(target_item, count)

        required = crafted["required"]
        steps = crafted["steps"]
        leftovers_out = leftovers
        lines: List[str] = []
        if required:
            lines.append("You are missing the following items:")
            for item, amt in required.items():
                lines.append(f"- {amt} {item}")
            lines.append("")
            lines.append("Once you have these items, here's your crafting plan:")
        else:
            lines.append("You have all items required to craft this item!")
            lines.append("Here's your crafting plan:")
        lines.append("")
        lines.extend(steps)
        if any("oak" in item for item in required) and "oak" not in target_item:
            lines.append("Note: Any variant of wood can be used for this recipe.")
        if leftovers_out:
            lines.append("")
            lines.append("You will have leftover:")
            for item, amt in leftovers_out.items():
                lines.append(f"- {amt} {item}")
        return "\n".join(lines)

    def _plan_equip_actions(
        self, snapshot: ScreenSnapshot, goal: str, allow_shield: bool = True
    ) -> Dict[str, Any]:
        inventory_slots = [
            slot
            for slot in snapshot.slots
            if slot.group in {"player_main", "player_hotbar"} and slot.item is not None
        ]
        armor_candidates = [
            slot
            for slot in inventory_slots
            if slot.item is not None and _infer_armor_slot(slot.item.name)
        ]
        material = self._goal_armor_material(goal)
        if material:
            armor_candidates = [
                slot
                for slot in armor_candidates
                if slot.item is not None
                and self._matches_armor_material(slot.item.name, material)
            ]

        current: Dict[str, str] = {}
        for slot in snapshot.slots:
            if slot.group == "player_armor" and slot.item is not None and slot.equip:
                current[slot.equip] = slot.item.name

        actions: List[Dict[str, Any]] = []
        equipped: Dict[str, str] = {}
        best: Dict[str, Tuple[int, SlotInfo]] = {}
        for slot in armor_candidates:
            item_name = slot.item.name
            equip_slot = _infer_armor_slot(item_name)
            if not equip_slot:
                continue
            score = _armor_score(item_name)
            if equip_slot not in best or score > best[equip_slot][0]:
                best[equip_slot] = (score, slot)

        if material:
            for equip_slot, (_, slot) in best.items():
                current_name = current.get(equip_slot)
                if current_name and self._matches_armor_material(current_name, material):
                    continue
                actions.append(
                    {"type": "equip", "sourceSlot": slot.slot, "target": equip_slot}
                )
                equipped[equip_slot] = slot.item.name
        else:
            for equip_slot, (score, slot) in best.items():
                current_name = current.get(equip_slot)
                current_score = _armor_score(current_name) if current_name else -1
                if score > current_score:
                    actions.append(
                        {"type": "equip", "sourceSlot": slot.slot, "target": equip_slot}
                    )
                    equipped[equip_slot] = slot.item.name

            if allow_shield:
                offhand_slot = next(
                    (slot for slot in snapshot.slots if slot.group == "player_offhand"),
                    None,
                )
                if offhand_slot and (offhand_slot.item is None):
                    shield = next(
                        (
                            slot
                            for slot in inventory_slots
                            if slot.item and slot.item.name == "shield"
                        ),
                        None,
                    )
                    if shield:
                        actions.append(
                            {"type": "equip", "sourceSlot": shield.slot, "target": "offhand"}
                        )
                        equipped["offhand"] = shield.item.name

        if actions:
            reason = "deterministic_equip"
        elif armor_candidates:
            reason = "already_equipped"
        else:
            reason = "no_matching_armor"
        if material:
            reason = f"{reason}:{material}"
        return {
            "ok": True,
            "actions": actions,
            "equipped": equipped,
            "reason": reason,
        }

    async def _plan_craft_from_goal(
        self, goal: str, available: Dict[str, int]
    ) -> Optional[Dict[str, Any]]:
        item_name = self._extract_item_from_goal(goal)
        if not item_name:
            return None
        goal_clean = goal.strip().lower()
        if not (
            self._goal_is_craft(goal)
            or goal_clean == item_name
            or goal_clean == f"minecraft:{item_name}"
        ):
            return None
        planned = await self.craft_item({"item": item_name, "count": 1}, execute=False)
        if planned.get("ok"):
            actions = planned.get("actions")
            return {
                "ok": True,
                "actions": actions if isinstance(actions, list) else [],
                "reason": "deterministic_craft_item",
                "planner": "rules:crafter",
                "plan_text": None,
                "warnings": [],
                "item": item_name,
            }
        plan_text = self._crafting_plan_text(item_name, 1, available)
        return {
            "ok": True,
            "actions": [],
            "reason": planned.get("error") or "crafting_missing_items",
            "planner": "rules:crafter",
            "plan_text": plan_text,
            "warnings": [],
            "item": item_name,
        }

    def _plan_text_only(
        self, goal: str, available: Dict[str, int]
    ) -> Optional[Dict[str, Any]]:
        item_name = self._extract_item_from_goal(goal)
        if not item_name:
            return None
        plan_text = self._crafting_plan_text(item_name, 1, available)
        return {
            "ok": True,
            "actions": [],
            "reason": "text_plan",
            "planner": "text",
            "plan_text": plan_text,
            "warnings": [],
            "item": item_name,
        }

    async def _plan_from_rules(
        self,
        goal: str,
        snapshot: ScreenSnapshot,
        available: Dict[str, int],
    ) -> Optional[Dict[str, Any]]:
        if self._goal_is_eat(goal):
            return self._plan_eat_actions(snapshot, goal)
        if self._goal_is_crafting_table(goal):
            planned = await self.craft_item(
                {"item": "crafting_table", "count": 1},
                execute=False,
            )
            if planned.get("ok"):
                actions = planned.get("actions")
                return {
                    "ok": True,
                    "actions": actions if isinstance(actions, list) else [],
                    "reason": "deterministic_craft_table",
                    "planner": "rules:crafting_table",
                    "plan_text": None,
                    "warnings": [],
                }
            plan_text = self._crafting_plan_text("crafting_table", 1, available)
            return {
                "ok": True,
                "actions": [],
                "reason": planned.get("error") or "crafting_missing_items",
                "planner": "rules:crafting_table",
                "plan_text": plan_text,
                "warnings": [],
            }
        if self._goal_is_equip(goal):
            planned = self._plan_equip_actions(snapshot, goal)
            planned["planner"] = "rules:equip"
            planned["warnings"] = []
            return planned
        craft_plan = await self._plan_craft_from_goal(goal, available)
        if craft_plan:
            return craft_plan
        return None

    def _is_planks(self, item_name: str) -> bool:
        return item_name.endswith("_planks")

    def _is_log(self, item_name: str) -> bool:
        return item_name.endswith("_log") or item_name.endswith("_wood") or item_name.endswith("_stem") or item_name.endswith("_hyphae")

    def _log_to_planks(self, item_name: str) -> Optional[str]:
        base = item_name
        if base.startswith("stripped_"):
            base = base[len("stripped_") :]
        for suffix in ("_log", "_wood", "_stem", "_hyphae"):
            if base.endswith(suffix):
                return base[: -len(suffix)] + "_planks"
        return None

    async def craft_item(self, params: Dict[str, Any], execute: bool = True) -> Dict[str, Any]:
        item_name = _normalize_item_name(params.get("item"))
        count = int(params.get("count", 1))
        if not item_name:
            return {"ok": False, "error": "missing_item"}
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        if snapshot is None:
            return {"ok": False, "error": "no_snapshot"}
        grid_info = self._crafting_grid(snapshot.slots)
        if not grid_info:
            await self._adapter.send_action({"type": "openInventory"}, self._headful_config())
            await asyncio.sleep(0.2)
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot is None:
                return {"ok": False, "error": "no_snapshot"}
            grid_info = self._crafting_grid(snapshot.slots)
        if not grid_info:
            return {"ok": False, "error": "no_crafting_grid"}
        grid, width, height = grid_info
        craft_output = next(
            (slot for slot in snapshot.slots if slot.group == "crafting_output"),
            None,
        )
        if craft_output is None:
            return {"ok": False, "error": "no_crafting_output"}

        actions: List[Dict[str, Any]] = []
        cursor = snapshot.cursor
        if cursor:
            target_slots = self._slots_by_group(
                snapshot.slots, ("player_main", "player_hotbar")
            )
            target = next(
                (
                    slot
                    for slot in target_slots
                    if slot.item
                    and slot.item.name == cursor.name
                    and slot.item.count < slot.item.max_count
                ),
                None,
            )
            if target is None:
                target = next((slot for slot in target_slots if slot.item is None), None)
            if not target:
                return {"ok": False, "error": "cursor_blocked"}
            actions.append(
                {"type": "clickSlot", "slot": target.slot, "button": 0, "action": "pickup"}
            )

        precrafted = 0
        if craft_output.item and craft_output.item.name == item_name:
            output_count = craft_output.item.count
            actions.append({"type": "quickMove", "slot": craft_output.slot})
            precrafted = 1
            if count <= output_count:
                if execute:
                    ok = await self._send_sequence(actions)
                    return {
                        "ok": ok,
                        "actions": len(actions),
                        "action_count": len(actions),
                        "crafts": precrafted,
                        "result_count": output_count,
                        "item": item_name,
                    }
                return {
                    "ok": True,
                    "actions": actions,
                    "action_count": len(actions),
                    "crafts": precrafted,
                    "result_count": output_count,
                    "item": item_name,
                }
            count = max(count - output_count, 0)

        recipe_book = self._get_recipe_book()
        recipes = [r for r in recipe_book.get_recipes(item_name) if self._recipe_fits(r, width, height)]
        if not recipes:
            return {"ok": False, "error": "no_recipe"}

        available = self._build_counts(
            snapshot.slots,
            ("player_main", "player_hotbar"),
        )
        best = max(recipes, key=lambda r: self._max_craftable(r, available))
        craftable = self._max_craftable(best, available)
        if craftable <= 0:
            missing = self._recipe_requirements(best)
            for k, v in list(missing.items()):
                missing[k] = max(v - available.get(k, 0), 0)
            return {"ok": False, "error": "missing_items", "missing": missing}

        per_craft = max(best.result_count, 1)
        times = min((count + per_craft - 1) // per_craft, craftable, int(params.get("max_times", 4)))
        if times <= 0:
            return {"ok": False, "error": "nothing_to_craft"}

        for slot in grid.values():
            if slot.item is not None:
                actions.append({"type": "quickMove", "slot": slot.slot})

        source_slots = [
            slot
            for slot in snapshot.slots
            if slot.group in {"player_main", "player_hotbar"} and slot.item is not None
        ]
        source_slots.sort(
            key=lambda slot: (0 if slot.group == "player_main" else 1, slot.slot)
        )
        slots_by_item: Dict[str, List[SlotInfo]] = {}
        slot_counts: Dict[int, int] = {}
        for slot in source_slots:
            slots_by_item.setdefault(slot.item.name, []).append(slot)
            slot_counts[slot.slot] = slot.item.count

        def take_source(item: str) -> Optional[SlotInfo]:
            for slot in slots_by_item.get(item, []):
                if slot_counts.get(slot.slot, 0) > 0:
                    slot_counts[slot.slot] -= 1
                    return slot
            return None

        def craft_once() -> bool:
            placements: List[Tuple[int, int, str]] = []
            if best.shaped and best.shape:
                for row_idx, row in enumerate(best.shape):
                    for col_idx, cell in enumerate(row):
                        if cell:
                            placements.append((col_idx, row_idx, cell))
            elif best.ingredients:
                flat = list(best.ingredients)
                idx = 0
                for row_idx in range(height):
                    for col_idx in range(width):
                        if idx >= len(flat):
                            break
                        placements.append((col_idx, row_idx, flat[idx]))
                        idx += 1
            else:
                return False

            for col_idx, row_idx, item in placements:
                target_slot = grid.get((col_idx, row_idx))
                if not target_slot:
                    return False
                source = take_source(item)
                if not source:
                    return False
                actions.extend(self._actions_move_one(source.slot, target_slot.slot))
            actions.append({"type": "quickMove", "slot": craft_output.slot})
            return True

        crafted = precrafted
        for _ in range(times):
            if craft_once():
                crafted += 1
            else:
                break

        if execute:
            ok = await self._send_sequence(actions)
            return {
                "ok": ok,
                "actions": len(actions),
                "action_count": len(actions),
                "crafts": crafted,
                "result_count": best.result_count,
                "item": best.result_name,
            }
        return {
            "ok": True,
            "actions": actions,
            "action_count": len(actions),
            "crafts": crafted,
            "result_count": best.result_count,
            "item": best.result_name,
        }
