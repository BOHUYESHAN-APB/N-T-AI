from __future__ import annotations

import asyncio
import inspect
import json
import math
import random
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


def _recipe_requirements_static(recipe: Recipe) -> Dict[str, int]:
    req: Dict[str, int] = {}
    if recipe.shaped and recipe.shape:
        for row in recipe.shape:
            for cell in row:
                if cell is None:
                    continue
                name = _normalize_item_name(cell)
                if name:
                    req[name] = req.get(name, 0) + 1
    elif recipe.ingredients:
        for cell in recipe.ingredients:
            name = _normalize_item_name(cell)
            if name:
                req[name] = req.get(name, 0) + 1
    return req


class ResourceGraph:
    """构建物品转换图（合成/熔炼等），支持后续规划使用。"""

    def __init__(
        self,
        recipe_book: RecipeBook,
        smelting_outputs: Dict[str, List[str]],
        extra_recipe_paths: Optional[List[Path]] = None,
    ) -> None:
        self.recipe_book = recipe_book
        self.smelting_outputs = smelting_outputs
        self.extra_recipe_paths = extra_recipe_paths or []
        self.edges_by_output: Dict[str, List[Dict[str, Any]]] = {}
        self._build_graph()

    def _add_edge(self, edge: Dict[str, Any]) -> None:
        out = edge.get("output")
        if not out:
            return
        out = _normalize_item_name(str(out))
        edge["output"] = out
        self.edges_by_output.setdefault(out, []).append(edge)

    def _build_graph(self) -> None:
        # 合成（来自 recipe_book）
        for item in self.recipe_book.craftable_items():
            recipes = self.recipe_book.get_recipes(item)
            for recipe in recipes:
                requirements = _recipe_requirements_static(recipe)
                if not requirements:
                    continue
                self._add_edge(
                    {
                        "type": "craft",
                        "output": recipe.result_name,
                        "count": max(int(recipe.result_count), 1),
                        "inputs": requirements,
                        "requires_table": True
                        if recipe.shaped and len(requirements) > 4
                        else False,
                    }
                )
        # 熔炼（内建映射）
        for output, inputs in self.smelting_outputs.items():
            for inp in inputs:
                self._add_edge(
                    {
                        "type": "smelt",
                        "output": output,
                        "count": 1,
                        "inputs": {_normalize_item_name(inp): 1},
                        "station": "furnace",
                    }
                )
        # 高炉（blasting）
        for output, inputs in BLASTING_OUTPUTS.items():
            for inp in inputs:
                self._add_edge(
                    {
                        "type": "smelt",
                        "output": output,
                        "count": 1,
                        "inputs": {_normalize_item_name(inp): 1},
                        "station": "blast_furnace",
                    }
                )
        # 烟熏炉（smoking）
        for output, inputs in SMOKING_OUTPUTS.items():
            for inp in inputs:
                self._add_edge(
                    {
                        "type": "smelt",
                        "output": output,
                        "count": 1,
                        "inputs": {_normalize_item_name(inp): 1},
                        "station": "smoker",
                    }
                )
        # 额外配方（为模组/自定义预留，放在 world/.mindcraft/recipes_custom.json）
        for path in self.extra_recipe_paths:
            try:
                if not path.exists():
                    continue
                with path.open("r", encoding="utf-8") as f:
                    data = json.load(f)
                if isinstance(data, list):
                    for edge in data:
                        if isinstance(edge, dict):
                            self._add_edge(edge)
            except Exception:
                continue

    def plan(
        self,
        target: str,
        count: int,
        inventory: Dict[str, int],
        allow_smelting: bool = True,
        chain: Optional[List[str]] = None,
        depth: int = 0,
        max_depth: int = 5,
    ) -> Dict[str, Any]:
        target = _normalize_item_name(target)
        if not target or count <= 0:
            return {"ok": False, "error": "invalid_target"}
        if chain is None:
            chain = []
        if target in chain or depth > max_depth:
            return {"ok": False, "error": "cycle_or_depth"}
        available = inventory.get(target, 0)
        if available >= count:
            return {
                "ok": True,
                "type": "use_existing",
                "output": target,
                "consume": count,
                "missing": 0,
                "substeps": [],
            }
        need = max(0, count - available)
        best_plan: Optional[Dict[str, Any]] = None
        edges = self.edges_by_output.get(target, [])
        for edge in edges:
            if edge.get("type") == "smelt" and not allow_smelting:
                continue
            # 需要多少次该配方
            per = max(int(edge.get("count", 1)), 1)
            times = int(math.ceil(need / per))
            substeps = []
            missing_total = 0
            new_chain = list(chain)
            new_chain.append(target)
            ok = True
            for inp, req in (edge.get("inputs") or {}).items():
                req_need = int(req) * times
                subplan = self.plan(
                    inp,
                    req_need,
                    inventory,
                    allow_smelting=allow_smelting,
                    chain=new_chain,
                    depth=depth + 1,
                    max_depth=max_depth,
                )
                substeps.append(subplan)
                if not subplan.get("ok"):
                    ok = False
                missing_total += int(subplan.get("missing", req_need))
            candidate = {
                "ok": ok,
                "type": edge.get("type"),
                "output": target,
                "count": count,
                "per_craft": per,
                "times": times,
                "inputs": edge.get("inputs"),
                "requires_table": edge.get("requires_table", False),
                "station": edge.get("station"),
                "substeps": substeps,
                "missing": missing_total if not ok else 0,
            }
            if best_plan is None:
                best_plan = candidate
            else:
                best_missing = int(best_plan.get("missing", 0))
                cand_missing = int(candidate.get("missing", 0))
                if cand_missing < best_missing:
                    best_plan = candidate
        if best_plan:
            return best_plan
        # 没有配方
        return {
            "ok": False,
            "type": "missing_recipe",
            "output": target,
            "missing": need,
            "substeps": [],
        }

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

    def craftable_items(self) -> List[str]:
        self._ensure_loaded()
        if not self._recipes:
            return []
        items: List[str] = []
        for key, raw_list in self._recipes.items():
            if not raw_list:
                continue
            try:
                item_id = int(key)
            except (TypeError, ValueError):
                continue
            name = self._id_to_name.get(item_id)
            if name:
                items.append(name)
        return sorted(set(items))

    def all_items(self) -> List[str]:
        self._ensure_loaded()
        return sorted(self._name_to_id.keys())


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

BASIC_UTILITY_BLOCKS = {
    "crafting_table",
    "furnace",
    "blast_furnace",
    "smoker",
    "brewing_stand",
    "enchanting_table",
    "lectern",
    "composter",
    "cauldron",
    "smithing_table",
    "anvil",
    "grindstone",
    "stonecutter",
    "loom",
    "cartography_table",
    "fletching_table",
}

CROP_BLOCKS = {
    "wheat",
    "potatoes",
    "carrots",
    "beetroots",
    "nether_wart",
    "sweet_berry_bush",
}

PILLAR_BLOCK_PREFERRED = [
    "dirt",
    "cobblestone",
    "stone",
    "granite",
    "diorite",
    "andesite",
    "sand",
    "gravel",
]

CONTAINER_EXCLUDE = {
    "trapped_chest",
}

CONTAINER_ITEMS = {
    "chest",
    "barrel",
    "ender_chest",
    "chest_minecart",
    "hopper",
    "hopper_minecart",
    "dropper",
    "dispenser",
    "shulker_box",
    "bundle",
    "decorated_pot",
    "chiseled_bookshelf",
}

SHULKER_COLORS = (
    "white",
    "orange",
    "magenta",
    "light_blue",
    "yellow",
    "lime",
    "pink",
    "gray",
    "light_gray",
    "cyan",
    "purple",
    "blue",
    "brown",
    "green",
    "red",
    "black",
)

CONTAINER_BLOCKS = {
    "chest",
    "trapped_chest",
    "barrel",
    "ender_chest",
    "shulker_box",
    "chiseled_bookshelf",
    "decorated_pot",
}
CONTAINER_BLOCKS.update({f"{color}_shulker_box" for color in SHULKER_COLORS})

CRAFTING_TABLE_BLOCK = "crafting_table"
SMELTING_BLOCKS = {"furnace", "blast_furnace", "smoker"}

BASIC_TOOL_ITEMS = {
    "shears",
    "flint_and_steel",
    "shield",
    "bow",
    "crossbow",
    "bucket",
}

TOOL_CANDIDATES = {
    "pickaxe": [
        "netherite_pickaxe",
        "diamond_pickaxe",
        "iron_pickaxe",
        "stone_pickaxe",
        "golden_pickaxe",
        "wooden_pickaxe",
    ],
    "axe": [
        "netherite_axe",
        "diamond_axe",
        "iron_axe",
        "stone_axe",
        "golden_axe",
        "wooden_axe",
    ],
    "shovel": [
        "netherite_shovel",
        "diamond_shovel",
        "iron_shovel",
        "stone_shovel",
        "golden_shovel",
        "wooden_shovel",
    ],
}

CN_ITEM_ALIASES = {
    "下界合金剑": "netherite_sword",
    "钻石剑": "diamond_sword",
    "黄金剑": "golden_sword",
    "金剑": "golden_sword",
    "铁剑": "iron_sword",
    "石剑": "stone_sword",
    "木剑": "wooden_sword",
    "下界合金镐子": "netherite_pickaxe",
    "下界合金镐": "netherite_pickaxe",
    "钻石镐子": "diamond_pickaxe",
    "钻石镐": "diamond_pickaxe",
    "黄金镐子": "golden_pickaxe",
    "金镐子": "golden_pickaxe",
    "黄金镐": "golden_pickaxe",
    "金镐": "golden_pickaxe",
    "铁镐子": "iron_pickaxe",
    "铁镐": "iron_pickaxe",
    "石镐子": "stone_pickaxe",
    "石镐": "stone_pickaxe",
    "木镐子": "wooden_pickaxe",
    "木镐": "wooden_pickaxe",
    "下界合金斧": "netherite_axe",
    "钻石斧": "diamond_axe",
    "黄金斧": "golden_axe",
    "金斧": "golden_axe",
    "铁斧": "iron_axe",
    "石斧": "stone_axe",
    "木斧": "wooden_axe",
    "下界合金铲": "netherite_shovel",
    "下界合金锹": "netherite_shovel",
    "钻石铲": "diamond_shovel",
    "钻石锹": "diamond_shovel",
    "黄金铲": "golden_shovel",
    "黄金锹": "golden_shovel",
    "金铲": "golden_shovel",
    "金锹": "golden_shovel",
    "铁铲": "iron_shovel",
    "铁锹": "iron_shovel",
    "石铲": "stone_shovel",
    "石锹": "stone_shovel",
    "木铲": "wooden_shovel",
    "木锹": "wooden_shovel",
    "下界合金锄": "netherite_hoe",
    "钻石锄": "diamond_hoe",
    "黄金锄": "golden_hoe",
    "金锄": "golden_hoe",
    "铁锄": "iron_hoe",
    "石锄": "stone_hoe",
    "木锄": "wooden_hoe",
    "工作台": "crafting_table",
    "熔炉": "furnace",
    "高炉": "blast_furnace",
    "烟熏炉": "smoker",
    "木板": "oak_planks",
    "木头": "oak_log",
    "木材": "oak_log",
    "木棍": "stick",
    "原木": "oak_log",
    "铁锭": "iron_ingot",
    "金锭": "gold_ingot",
    "钻石": "diamond",
}

REDSTONE_KEYWORDS = (
    "redstone",
    "repeater",
    "comparator",
    "piston",
    "observer",
    "hopper",
    "dropper",
    "dispenser",
    "daylight_detector",
    "lever",
    "button",
    "pressure_plate",
    "tripwire",
    "target",
    "note_block",
    "tnt",
    "rail",
    "minecart",
)

HOSTILE_ENTITY_TYPES = {
    "zombie",
    "skeleton",
    "creeper",
    "spider",
    "cave_spider",
    "enderman",
    "witch",
    "slime",
    "magma_cube",
    "phantom",
    "drowned",
    "husk",
    "stray",
    "pillager",
    "vindicator",
    "evoker",
    "ravager",
    "blaze",
    "ghast",
    "hoglin",
    "piglin",
    "piglin_brute",
    "guardian",
    "elder_guardian",
    "silverfish",
    "endermite",
}

HOSTILE_PRIORITY = {
    "creeper": 5,
    "witch": 4,
    "evoker": 4,
    "ravager": 4,
    "ghast": 4,
    "blaze": 3,
    "skeleton": 3,
    "stray": 3,
    "pillager": 3,
    "phantom": 3,
    "enderman": 3,
    "zombie": 2,
    "husk": 2,
    "drowned": 2,
    "spider": 2,
    "cave_spider": 2,
    "magma_cube": 2,
    "slime": 2,
    "piglin_brute": 2,
}

SMELTING_OUTPUTS: Dict[str, List[str]] = {
    "iron_ingot": ["raw_iron", "iron_ore", "deepslate_iron_ore"],
    "gold_ingot": ["raw_gold", "gold_ore", "deepslate_gold_ore", "nether_gold_ore"],
    "copper_ingot": ["raw_copper", "copper_ore", "deepslate_copper_ore"],
    "cooked_beef": ["raw_beef"],
    "cooked_porkchop": ["raw_porkchop"],
    "cooked_chicken": ["raw_chicken"],
    "cooked_mutton": ["raw_mutton"],
    "cooked_rabbit": ["raw_rabbit"],
    "cooked_cod": ["raw_cod"],
    "cooked_salmon": ["raw_salmon"],
    "baked_potato": ["potato"],
    "dried_kelp": ["kelp"],
    "stone": ["cobblestone"],
    "smooth_stone": ["stone"],
    "glass": ["sand", "red_sand"],
    "brick": ["clay_ball"],
}

SMELT_LOG_OUTPUTS = {"charcoal"}

BLASTING_OUTPUTS: Dict[str, List[str]] = {
    "iron_ingot": ["raw_iron", "iron_ore", "deepslate_iron_ore"],
    "gold_ingot": ["raw_gold", "gold_ore", "deepslate_gold_ore", "nether_gold_ore"],
    "copper_ingot": ["raw_copper", "copper_ore", "deepslate_copper_ore"],
}

SMOKING_OUTPUTS: Dict[str, List[str]] = {
    "cooked_beef": ["raw_beef"],
    "cooked_porkchop": ["raw_porkchop"],
    "cooked_chicken": ["raw_chicken"],
    "cooked_mutton": ["raw_mutton"],
    "cooked_rabbit": ["raw_rabbit"],
    "cooked_cod": ["raw_cod"],
    "cooked_salmon": ["raw_salmon"],
    "baked_potato": ["potato"],
    "dried_kelp": ["kelp"],
}

FUEL_PRIORITY = (
    "coal",
    "charcoal",
    "coal_block",
    "dried_kelp_block",
    "dried_kelp",
    "blaze_rod",
)

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
        alert_callback: Optional[Callable[[str, Dict[str, Any] | None], Any]] = None,
        data_root: Optional[Path] = None,
    ) -> None:
        self._logger = logger
        self._log_append = log_append
        self._adapter = adapter
        self._config_provider = config_provider
        self._lock = asyncio.Lock()
        self._recipe_book: Optional[RecipeBook] = None
        self._resource_graph: Optional[ResourceGraph] = None
        self._data_root = data_root
        self._llm = LLMService()
        self._memory = MemorySystemService()
        self.last_plan: Optional[Dict[str, Any]] = None
        self._person_service = PersonService()
        self._alert_callback = alert_callback
        self._mindcraft_docs_user_id = "mindcraft_docs"
        self._mindcraft_docs_indexed: set[str] = set()
        self._craftable_catalog: Optional[Dict[str, Any]] = None
        self._registry_lock = asyncio.Lock()
        self._container_registry_cache: Optional[Dict[str, Any]] = None
        self._container_registry_path: Optional[Path] = None
        self._container_registry_loaded_at = 0.0
        self._cancel_requested = False
        self._autonomy_last_guard = 0.0
        self._autonomy_last_gather = 0.0
        self._autonomy_last_look = 0.0
        self._autonomy_last_idle = 0.0
        self._autonomy_last_crop = 0.0
        self._autonomy_last_patrol = 0.0

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

    def _get_resource_graph(self) -> ResourceGraph:
        if self._resource_graph is not None:
            return self._resource_graph
        recipe_book = self._get_recipe_book()
        extra_paths: List[Path] = []
        try:
            base_dir = self._registry_base_dir()
            extra_paths.extend(
                [
                    base_dir / "recipes_custom.json",
                    base_dir / "recipes_brewing.json",
                    base_dir / "recipes_smithing.json",
                    base_dir / "recipes_trading.json",
                    base_dir / "recipes_blasting.json",
                    base_dir / "recipes_smoking.json",
                    base_dir / "recipes_enchanting.json",
                ]
            )
        except Exception:
            pass
        self._resource_graph = ResourceGraph(recipe_book, SMELTING_OUTPUTS, extra_paths)
        return self._resource_graph

    def _config(self) -> Dict[str, Any]:
        cfg = self._config_provider() or {}
        return cfg if isinstance(cfg, dict) else {}

    def _headful_config(self) -> Dict[str, Any]:
        cfg = self._config()
        return cfg.get("headful", cfg)

    def _debug_enabled(self, params: Optional[Dict[str, Any]] = None) -> bool:
        if params and "debug" in params:
            return bool(params.get("debug"))
        cfg = self._headful_config()
        return bool(cfg.get("debug", False))

    def _debug_log(self, message: str, params: Optional[Dict[str, Any]] = None) -> None:
        if not self._debug_enabled(params):
            return
        self._log_append(f"[headful-debug] {message}")

    async def _emit_alert(
        self, message: str, payload: Optional[Dict[str, Any]] = None
    ) -> None:
        if not message:
            return
        alert_payload = {"message": message, "timestamp": time.time()}
        if payload:
            alert_payload.update(payload)
        if self._alert_callback:
            try:
                result = self._alert_callback(message, alert_payload)
                if inspect.isawaitable(result):
                    await result
            except Exception as exc:
                self._log_append(f"[llm-alert] callback failed: {exc}")
        self._log_append(f"[llm-alert] {message}")

    def _current_dimension(self) -> str:
        state = getattr(self._adapter, "last_state", None)
        if isinstance(state, dict):
            return str(state.get("dimension") or "")
        return ""

    def _registry_base_dir(self) -> Path:
        cfg = self._headful_config()
        state = getattr(self._adapter, "last_state", None)
        world_path = None
        if isinstance(state, dict):
            world_path = state.get("worldPath") or state.get("savePath") or state.get("world_path")
        if world_path:
            return Path(str(world_path)) / ".mindcraft"
        fallback = cfg.get("world_cache_dir") or cfg.get("cache_dir")
        if fallback:
            return Path(str(fallback))
        return Path(__file__).resolve().parent / ".mindcraft"

    def _registry_file_path(self) -> Path:
        return self._registry_base_dir() / "container_registry.json"

    async def _load_container_registry(self) -> Dict[str, Any]:
        async with self._registry_lock:
            path = self._registry_file_path()
            if self._container_registry_cache is not None and path == self._container_registry_path:
                return self._container_registry_cache
            data: Dict[str, Any] = {"version": 1, "containers": {}, "updated_at": 0}
            try:
                if path.exists():
                    with path.open("r", encoding="utf-8") as f:
                        loaded = json.load(f)
                    if isinstance(loaded, dict):
                        data.update(loaded)
            except Exception:
                data = {"version": 1, "containers": {}, "updated_at": 0}
            self._container_registry_cache = data
            self._container_registry_path = path
            self._container_registry_loaded_at = time.time()
            return data

    async def _save_container_registry(self, registry: Dict[str, Any]) -> None:
        async with self._registry_lock:
            path = self._registry_file_path()
            path.parent.mkdir(parents=True, exist_ok=True)
            registry["updated_at"] = time.time()
            tmp_path = path.with_suffix(".tmp")
            with tmp_path.open("w", encoding="utf-8") as f:
                json.dump(registry, f, ensure_ascii=True, indent=2)
            tmp_path.replace(path)
            self._container_registry_cache = registry
            self._container_registry_path = path
            self._container_registry_loaded_at = time.time()

    def _container_key(self, pos: Dict[str, Any]) -> Optional[str]:
        try:
            x = int(pos.get("x"))
            y = int(pos.get("y"))
            z = int(pos.get("z"))
        except (TypeError, ValueError, AttributeError):
            return None
        dimension = self._current_dimension()
        return f"{dimension}:{x}:{y}:{z}"

    async def _register_found_positions(self, positions: List[Dict[str, Any]]) -> None:
        if not positions:
            return
        registry = await self._load_container_registry()
        containers = registry.setdefault("containers", {})
        updated = False
        now = time.time()
        dimension = self._current_dimension()
        for pos in positions:
            key = self._container_key(pos)
            if not key:
                continue
            entry = containers.get(key, {})
            entry.update(
                {
                    "x": int(pos.get("x")),
                    "y": int(pos.get("y")),
                    "z": int(pos.get("z")),
                    "dimension": dimension,
                    "block": str(pos.get("block", entry.get("block", ""))),
                    "last_seen": now,
                }
            )
            containers[key] = entry
            updated = True
        if updated:
            await self._save_container_registry(registry)

    async def _update_container_registry(
        self, pos: Dict[str, Any], snapshot: ScreenSnapshot
    ) -> None:
        key = self._container_key(pos)
        if not key:
            return
        items: Dict[str, int] = {}
        for slot in snapshot.slots:
            if slot.group.startswith("container") and slot.item is not None:
                items[slot.item.name] = items.get(slot.item.name, 0) + slot.item.count
        registry = await self._load_container_registry()
        containers = registry.setdefault("containers", {})
        now = time.time()
        entry = containers.get(key, {})
        entry.update(
            {
                "x": int(pos.get("x")),
                "y": int(pos.get("y")),
                "z": int(pos.get("z")),
                "dimension": self._current_dimension(),
                "block": str(pos.get("block", entry.get("block", ""))),
                "last_seen": now,
                "last_open": now,
                "items": items,
            }
        )
        containers[key] = entry
        await self._save_container_registry(registry)

    def _registry_positions_within_radius(
        self, registry: Dict[str, Any], radius: int
    ) -> List[Dict[str, Any]]:
        player_pos = self._player_pos()
        if not player_pos:
            return []
        containers = registry.get("containers") if isinstance(registry, dict) else None
        if not isinstance(containers, dict):
            return []
        dimension = self._current_dimension()
        radius = max(1, int(radius))
        radius_sq = radius * radius
        positions: List[Dict[str, Any]] = []
        for entry in containers.values():
            if not isinstance(entry, dict):
                continue
            if dimension and entry.get("dimension") and entry.get("dimension") != dimension:
                continue
            try:
                dx = float(entry.get("x")) - float(player_pos[0])
                dy = float(entry.get("y")) - float(player_pos[1])
                dz = float(entry.get("z")) - float(player_pos[2])
            except (TypeError, ValueError):
                continue
            if dx * dx + dy * dy + dz * dz > radius_sq:
                continue
            positions.append(
                {
                    "x": entry.get("x"),
                    "y": entry.get("y"),
                    "z": entry.get("z"),
                    "block": entry.get("block", ""),
                }
            )
        return positions

    def _normalize_block_name(self, name: str | None) -> str:
        raw = (name or "").strip().lower()
        if not raw:
            return ""
        if raw.startswith("minecraft:"):
            return raw
        return f"minecraft:{raw}"

    async def _find_blocks(
        self,
        blocks: List[str],
        radius: int = 8,
        max_results: int = 1,
        timeout: float = 2.0,
    ) -> Dict[str, Any]:
        normalized = [self._normalize_block_name(b) for b in blocks if b]
        if not normalized:
            return {"ok": False, "error": "missing_block"}
        action: Dict[str, Any] = {
            "type": "findBlock",
            "radius": int(radius),
            "maxResults": int(max_results),
        }
        if len(normalized) == 1:
            action["block"] = normalized[0]
        else:
            action["blocks"] = normalized
        result = await self._adapter.request_action(
            action, self._headful_config(), timeout=timeout
        )
        if not isinstance(result, dict):
            return {"ok": False, "error": "find_block_timeout"}
        return result

    async def _find_mature_crops(
        self,
        blocks: List[str],
        radius: int = 8,
        max_results: int = 1,
        timeout: float = 2.0,
    ) -> Dict[str, Any]:
        normalized = [self._normalize_block_name(b) for b in blocks if b]
        if not normalized:
            return {"ok": False, "error": "missing_block"}
        action: Dict[str, Any] = {
            "type": "findCrop",
            "radius": int(radius),
            "maxResults": int(max_results),
        }
        if len(normalized) == 1:
            action["block"] = normalized[0]
        else:
            action["blocks"] = normalized
        result = await self._adapter.request_action(
            action, self._headful_config(), timeout=timeout
        )
        if not isinstance(result, dict):
            return {"ok": False, "error": "find_crop_timeout"}
        return result

    def _player_pos(self) -> Optional[Tuple[float, float, float]]:
        state = getattr(self._adapter, "last_state", None)
        if not isinstance(state, dict):
            return None
        try:
            return float(state.get("x")), float(state.get("y")), float(state.get("z"))
        except (TypeError, ValueError):
            return None

    async def _ensure_hotbar_slot_for_item(
        self, snapshot: ScreenSnapshot, item_names: Iterable[str]
    ) -> Tuple[Optional[int], ScreenSnapshot]:
        names = {_normalize_item_name(n) for n in item_names if n}
        if not names:
            return None, snapshot
        target_slot = next(
            (
                slot
                for slot in snapshot.slots
                if slot.item is not None and slot.item.name in names
            ),
            None,
        )
        if target_slot is None:
            return None, snapshot
        hotbar_index = self._hotbar_index_for_slot(snapshot, target_slot)
        if hotbar_index is None:
            hotbar_slots = [s for s in snapshot.slots if s.group == "player_hotbar"]
            hotbar_slots.sort(key=lambda s: (s.item is not None, s.x, s.y, s.slot))
            target_hotbar = next((s for s in hotbar_slots if s.item is None), None) or (
                hotbar_slots[0] if hotbar_slots else None
            )
            if target_hotbar and target_hotbar.slot != target_slot.slot:
                await self._send_sequence(
                    [
                        {
                            "type": "moveStack",
                            "fromSlot": target_slot.slot,
                            "toSlot": target_hotbar.slot,
                        }
                    ]
                )
                raw = await self._get_snapshot(refresh=True)
                snapshot = ScreenSnapshot.from_dict(raw) or snapshot
                target_slot = target_hotbar
                hotbar_index = self._hotbar_index_for_slot(snapshot, target_slot)
        if hotbar_index is not None:
            await self._send_sequence([{"type": "hotbar", "slot": hotbar_index}])
        return hotbar_index, snapshot

    async def _place_block_from_hotbar(
        self,
        snapshot: ScreenSnapshot,
        face: str = "up",
        look_duration_ms: int = 200,
    ) -> bool:
        player_pos = self._player_pos()
        if not player_pos:
            return False
        x, y, z = player_pos
        candidates = [
            {"x": int(x), "y": int(y) - 1, "z": int(z)},
            {"x": int(x) + 1, "y": int(y) - 1, "z": int(z)},
            {"x": int(x) - 1, "y": int(y) - 1, "z": int(z)},
            {"x": int(x), "y": int(y) - 1, "z": int(z) + 1},
            {"x": int(x), "y": int(y) - 1, "z": int(z) - 1},
        ]
        for base in candidates:
            await self._look_at_position(base, duration_ms=look_duration_ms)
            if await self._use_block_at(base, str(face)):
                return True
        # 最后尝试 useTarget 兜底
        await self._adapter.send_action({"type": "useTarget"}, self._headful_config())
        return False

    def _player_yaw_pitch(self) -> Optional[Tuple[float, float]]:
        state = getattr(self._adapter, "last_state", None)
        if not isinstance(state, dict):
            return None
        try:
            return float(state.get("yaw", 0.0)), float(state.get("pitch", 0.0))
        except (TypeError, ValueError):
            return None

    def _compute_yaw_pitch(
        self, target_x: float, target_y: float, target_z: float, eye_height: float = 1.62
    ) -> Optional[Tuple[float, float]]:
        pos = self._player_pos()
        if not pos:
            return None
        dx = target_x - pos[0]
        dz = target_z - pos[2]
        dy = target_y - (pos[1] + eye_height)
        if dx == 0 and dz == 0:
            return None
        yaw = math.degrees(math.atan2(dz, dx)) - 90.0
        dist_xz = math.sqrt(dx * dx + dz * dz)
        pitch = -math.degrees(math.atan2(dy, dist_xz))
        return yaw, pitch

    async def _look_at_position(
        self,
        pos: Dict[str, Any],
        duration_ms: int = 200,
        eye_height: float = 1.62,
    ) -> bool:
        try:
            x = float(pos.get("x"))
            y = float(pos.get("y"))
            z = float(pos.get("z"))
        except (TypeError, ValueError, AttributeError):
            return False
        yaw_pitch = self._compute_yaw_pitch(x + 0.5, y + 0.5, z + 0.5, eye_height=eye_height)
        if not yaw_pitch:
            return False
        yaw, pitch = yaw_pitch
        await self._adapter.send_action(
            {"type": "lookSmooth", "yaw": yaw, "pitch": pitch, "durationMs": int(duration_ms)},
            self._headful_config(),
        )
        return True

    def _nearby_entities(self) -> List[Dict[str, Any]]:
        state = getattr(self._adapter, "last_state", None)
        if not isinstance(state, dict):
            return []
        raw = state.get("nearbyEntities")
        if isinstance(raw, dict):
            items = raw.get("items")
        else:
            items = None
        if not isinstance(items, list):
            return []
        return [item for item in items if isinstance(item, dict)]

    def _normalize_entity_type(self, name: str | None) -> str:
        raw = (name or "").strip().lower()
        if not raw:
            return ""
        if raw.startswith("minecraft:"):
            return raw
        return f"minecraft:{raw}"

    def _match_entity_type(self, entity: Dict[str, Any], target: str) -> bool:
        raw_type = str(entity.get("type", "")).lower()
        if not raw_type:
            return False
        norm = self._normalize_entity_type(target)
        return raw_type == norm or raw_type.endswith(f":{target}")

    def _select_nearest_hostile_entity(
        self, max_distance_sq: float = 144.0
    ) -> Optional[Dict[str, Any]]:
        best = None
        best_priority = -1
        best_dist = max_distance_sq
        for e in self._nearby_entities():
            etype = str(e.get("type", "")).split(":")[-1]
            if etype not in HOSTILE_ENTITY_TYPES:
                continue
            dist = float(e.get("dist", 1e9))
            if dist > max_distance_sq:
                continue
            priority = int(HOSTILE_PRIORITY.get(etype, 0))
            if priority > best_priority or (priority == best_priority and dist < best_dist):
                best = e
                best_priority = priority
                best_dist = dist
        return best

    def _select_nearest_entity(
        self,
        target_type: Optional[str] = None,
        target_name: Optional[str] = None,
        max_distance: Optional[float] = None,
    ) -> Optional[Dict[str, Any]]:
        candidates = self._nearby_entities()
        if target_type:
            candidates = [
                e for e in candidates if self._match_entity_type(e, target_type)
            ]
        if target_name:
            name = str(target_name).lower()
            candidates = [
                e
                for e in candidates
                if str(e.get("name", "")).lower() == name
            ]
        if max_distance is not None:
            max_sq = max_distance * max_distance
            candidates = [
                e for e in candidates if float(e.get("dist", 1e9)) <= max_sq
            ]
        if not candidates:
            return None
        candidates.sort(key=lambda e: float(e.get("dist", 1e9)))
        return candidates[0]

    async def _move_near_position(
        self,
        pos: Dict[str, Any],
        distance: float = 4.0,
        timeout: float = 6.0,
        horizontal_only: bool = False,
    ) -> bool:
        try:
            x = float(pos.get("x"))
            y = float(pos.get("y"))
            z = float(pos.get("z"))
        except (TypeError, ValueError, AttributeError):
            return False
        target_dist_sq = distance * distance
        start = time.time()
        current = self._player_pos()
        if current:
            dx = current[0] - x
            dy = current[1] - y
            dz = current[2] - z
            if horizontal_only:
                if dx * dx + dz * dz <= target_dist_sq:
                    return True
            elif dx * dx + dy * dy + dz * dz <= target_dist_sq:
                return True
        await self._adapter.send_action(
            {"type": "pathfindTo", "x": x, "y": y, "z": z},
            self._headful_config(),
        )
        while time.time() - start < timeout:
            await asyncio.sleep(0.2)
            current = self._player_pos()
            if not current:
                continue
            dx = current[0] - x
            dy = current[1] - y
            dz = current[2] - z
            if horizontal_only:
                if dx * dx + dz * dz <= target_dist_sq:
                    return True
            elif dx * dx + dy * dy + dz * dz <= target_dist_sq:
                return True
        return False

    async def _use_block_at(
        self, pos: Dict[str, Any], face: str = "up"
    ) -> bool:
        try:
            x = int(pos.get("x"))
            y = int(pos.get("y"))
            z = int(pos.get("z"))
        except (TypeError, ValueError, AttributeError):
            return False
        return await self._adapter.send_action(
            {"type": "useBlock", "x": x, "y": y, "z": z, "face": face},
            self._headful_config(),
        )

    def _snapshot_has_container(self, snapshot: ScreenSnapshot) -> bool:
        return any(slot.group.startswith("container") for slot in snapshot.slots)

    def _snapshot_has_smelting_container(self, snapshot: ScreenSnapshot) -> bool:
        return any(
            slot.group in {"container_input", "container_fuel", "container_output"}
            for slot in snapshot.slots
        )

    def _container_priority(self, block_name: str) -> int:
        name = self._normalize_block_name(block_name).split(":", 1)[1]
        if name.endswith("_shulker_box") or name == "shulker_box":
            return 0
        if name in {"chest", "trapped_chest"}:
            return 1
        if name == "barrel":
            return 2
        if name in SMELTING_BLOCKS:
            return 3
        if name == "ender_chest":
            return 99
        return 5

    def _sort_container_positions(
        self,
        positions: List[Dict[str, Any]],
        registry: Optional[Dict[str, Any]] = None,
        remaining: Optional[Dict[str, int]] = None,
        smelt_groups: Optional[Dict[str, Any]] = None,
    ) -> List[Dict[str, Any]]:
        player_pos = self._player_pos()
        containers = {}
        if isinstance(registry, dict):
            containers = registry.get("containers") or {}
        group_items = {}
        group_remaining = {}
        if isinstance(smelt_groups, dict):
            group_items = smelt_groups.get("group_items") or {}
            group_remaining = smelt_groups.get("group_remaining") or {}
        now = time.time()

        def distance_sq(pos: Dict[str, Any]) -> float:
            if not player_pos:
                return 0.0
            try:
                dx = float(pos.get("x")) - float(player_pos[0])
                dy = float(pos.get("y")) - float(player_pos[1])
                dz = float(pos.get("z")) - float(player_pos[2])
            except (TypeError, ValueError):
                return 0.0
            return dx * dx + dy * dy + dz * dz

        def match_score(entry: Dict[str, Any]) -> int:
            if not remaining:
                return 0
            items = entry.get("items")
            if not isinstance(items, dict):
                return 0
            score = 0
            for item, need in remaining.items():
                if need <= 0:
                    continue
                count = items.get(item, 0)
                if count > 0:
                    score += min(int(need), int(count))
            if group_items and group_remaining:
                for group_id, candidates in group_items.items():
                    needed = int(group_remaining.get(group_id, 0))
                    if needed <= 0:
                        continue
                    for cand in candidates:
                        count = items.get(cand, 0)
                        if count > 0:
                            score += min(needed, int(count))
                            break
            return score

        return sorted(
            positions,
            key=lambda pos: (
                self._container_priority(str(pos.get("block", ""))),
                0 if containers.get(self._container_key(pos) or "") else 1,
                -match_score(containers.get(self._container_key(pos) or "", {})),
                now - float(containers.get(self._container_key(pos) or "", {}).get("last_seen", now)),
                distance_sq(pos),
            ),
        )

    def _build_smelt_input_groups(
        self, needed: Dict[str, int], target_item: str
    ) -> Optional[Dict[str, Any]]:
        if not needed:
            return None
        item_to_group: Dict[str, str] = {}
        group_items: Dict[str, List[str]] = {}
        group_remaining: Dict[str, int] = {}
        for output, inputs in SMELTING_OUTPUTS.items():
            if target_item in inputs:
                continue
            required = 0
            for inp in inputs:
                required = max(required, int(needed.get(inp, 0)))
            if required <= 0:
                continue
            group_id = f"smelt:{output}"
            group_items[group_id] = list(dict.fromkeys(inputs))
            group_remaining[group_id] = required
            for inp in inputs:
                item_to_group[inp] = group_id
        if not item_to_group:
            return None
        return {
            "item_to_group": item_to_group,
            "group_items": group_items,
            "group_remaining": group_remaining,
        }

    def _container_signature(self, snapshot: ScreenSnapshot) -> Tuple[Tuple[int, str, int], ...]:
        items: List[Tuple[int, str, int]] = []
        for slot in snapshot.slots:
            if slot.group in {
                "container",
                "container_input",
                "container_output",
                "container_fuel",
            }:
                if slot.item:
                    items.append((slot.slot, slot.item.name, slot.item.count))
                else:
                    items.append((slot.slot, "", 0))
        return tuple(items)

    async def _stabilize_container_snapshot(
        self, snapshot: ScreenSnapshot, settle_ms: int
    ) -> ScreenSnapshot:
        settle_ms = max(0, int(settle_ms))
        if settle_ms <= 0:
            return snapshot
        last_sig = self._container_signature(snapshot)
        last_snapshot = snapshot
        deadline = time.time() + (settle_ms / 1000.0)
        while time.time() < deadline:
            await asyncio.sleep(0.1)
            raw = await self._get_snapshot(refresh=True)
            fresh = ScreenSnapshot.from_dict(raw)
            if fresh is None:
                continue
            if not (fresh.screen_open and self._snapshot_has_container(fresh)):
                continue
            sig = self._container_signature(fresh)
            if sig == last_sig:
                return fresh
            last_sig = sig
            last_snapshot = fresh
        return last_snapshot

    async def _wait_for_container(
        self, timeout: float = 2.0
    ) -> Optional[ScreenSnapshot]:
        start = time.time()
        while time.time() - start < timeout:
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot and snapshot.screen_open and self._snapshot_has_container(snapshot):
                return snapshot
            await asyncio.sleep(0.2)
        return None

    async def _wait_for_screen_closed(self, timeout: float = 1.2) -> bool:
        start = time.time()
        while time.time() - start < timeout:
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot and not snapshot.screen_open:
                return True
            await asyncio.sleep(0.1)
        return False

    async def _wait_for_smelting_container(
        self, timeout: float = 2.0
    ) -> Optional[ScreenSnapshot]:
        start = time.time()
        while time.time() - start < timeout:
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot and snapshot.screen_open and self._snapshot_has_smelting_container(snapshot):
                return snapshot
            await asyncio.sleep(0.2)
        return None

    async def _wait_for_crafting_table(
        self, timeout: float = 2.0
    ) -> Optional[ScreenSnapshot]:
        start = time.time()
        while time.time() - start < timeout:
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot and snapshot.screen_open:
                handler = (snapshot.handler or "").lower()
                title = str(snapshot.title or "")
                if "crafting" in handler and "player" not in handler:
                    return snapshot
                if any(key in title for key in ("工作台", "Crafting", "crafting")):
                    return snapshot
                grid_info = self._crafting_grid(snapshot.slots)
                if grid_info:
                    _, width, height = grid_info
                    if width >= 3 and height >= 3:
                        return snapshot
            await asyncio.sleep(0.2)
        return None

    async def _wait_for_handler(
        self,
        handler_keywords: Tuple[str, ...],
        title_keywords: Tuple[str, ...],
        timeout: float = 2.0,
    ) -> Optional[ScreenSnapshot]:
        start = time.time()
        while time.time() - start < timeout:
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot and snapshot.screen_open:
                handler = (snapshot.handler or "").lower()
                title = str(snapshot.title or "")
                if any(keyword in handler for keyword in handler_keywords):
                    return snapshot
                if any(keyword in title for keyword in title_keywords):
                    return snapshot
            await asyncio.sleep(0.2)
        return None

    async def _wait_for_brewing_stand(
        self, timeout: float = 2.0
    ) -> Optional[ScreenSnapshot]:
        return await self._wait_for_handler(
            ("brewing",),
            ("酿造", "Brewing", "brewing"),
            timeout=timeout,
        )

    async def _wait_for_smithing_table(
        self, timeout: float = 2.0
    ) -> Optional[ScreenSnapshot]:
        return await self._wait_for_handler(
            ("smithing",),
            ("锻造", "Smithing", "smithing"),
            timeout=timeout,
        )

    async def _wait_for_enchanting_table(
        self, timeout: float = 2.0
    ) -> Optional[ScreenSnapshot]:
        return await self._wait_for_handler(
            ("enchant",),
            ("附魔", "Enchanting", "enchant"),
            timeout=timeout,
        )

    async def _wait_for_trade_screen(
        self, timeout: float = 2.0
    ) -> Optional[ScreenSnapshot]:
        return await self._wait_for_handler(
            ("merchant", "villager"),
            ("交易", "Trading", "Merchant", "Villager"),
            timeout=timeout,
        )

    def _is_redstone_item(self, item_name: str) -> bool:
        return any(keyword in item_name for keyword in REDSTONE_KEYWORDS)

    def _is_tool_item(self, item_name: str) -> bool:
        return item_name.endswith(("pickaxe", "axe", "shovel", "hoe"))

    def _is_weapon_item(self, item_name: str) -> bool:
        return item_name.endswith("sword") or item_name in {"bow", "crossbow", "shield"}

    def _is_container_item(self, item_name: str) -> bool:
        if item_name in CONTAINER_EXCLUDE:
            return False
        if item_name in CONTAINER_ITEMS:
            return True
        if item_name.endswith("_shulker_box") or item_name.endswith("_bundle"):
            return True
        if item_name.endswith("_chest_boat") or item_name.endswith("_chest_raft"):
            return True
        return False

    def _merge_requirements(
        self, base: Dict[str, int], add: Dict[str, int]
    ) -> Dict[str, int]:
        for item, count in add.items():
            base[item] = base.get(item, 0) + count
        return base

    def _compute_transfer_requirements(
        self,
        item_name: str,
        count: int,
        inventory_counts: Dict[str, int],
        available_for_choice: Dict[str, int],
        allow_smelting: bool = True,
        chain: Optional[List[str]] = None,
    ) -> Dict[str, int]:
        if count <= 0 or not item_name:
            return {}
        if chain is None:
            chain = []
        if item_name in chain:
            return {}

        available_count = inventory_counts.get(item_name, 0)
        if available_count >= count:
            inventory_counts[item_name] = available_count - count
            if available_for_choice.get(item_name, 0) >= count:
                available_for_choice[item_name] = available_for_choice.get(item_name, 0) - count
            return {}
        if available_count > 0:
            count -= available_count
            inventory_counts[item_name] = 0
            if available_for_choice.get(item_name, 0) >= available_count:
                available_for_choice[item_name] = available_for_choice.get(item_name, 0) - available_count

        if allow_smelting and self._is_smelt_output(item_name):
            return {item_name: count}

        recipe_book = self._get_recipe_book()
        recipes = recipe_book.get_recipes(item_name)
        if not recipes:
            return {item_name: count}
        recipe = self._select_recipe(recipes, available_for_choice) or recipes[0]
        requirements = self._recipe_requirements(recipe)
        crafted_per = max(recipe.result_count, 1)
        batch_count = int(math.ceil(count / crafted_per))
        total: Dict[str, int] = {}
        next_chain = list(chain)
        next_chain.append(item_name)
        for req_item, req_count in requirements.items():
            needed = req_count * batch_count
            child = self._compute_transfer_requirements(
                req_item,
                needed,
                inventory_counts,
                available_for_choice,
                allow_smelting=allow_smelting,
                chain=next_chain,
            )
            self._merge_requirements(total, child)
        return total

    def _compute_transfer_requirements_from_inventory(
        self,
        item_name: str,
        count: int,
        inventory_counts: Dict[str, int],
        available_for_choice: Dict[str, int],
        allow_smelting: bool = True,
        chain: Optional[List[str]] = None,
    ) -> Dict[str, int]:
        if count <= 0 or not item_name:
            return {}
        if chain is None:
            chain = []
        if item_name in chain:
            return {}

        available_count = inventory_counts.get(item_name, 0)
        if available_count >= count:
            inventory_counts[item_name] = available_count - count
            return {}
        if available_count > 0:
            count -= available_count
            inventory_counts[item_name] = 0

        if allow_smelting and self._is_smelt_output(item_name):
            return {item_name: count}

        recipe_book = self._get_recipe_book()
        recipes = recipe_book.get_recipes(item_name)
        if not recipes:
            return {item_name: count}
        recipe = self._select_recipe(recipes, available_for_choice) or recipes[0]
        requirements = self._recipe_requirements(recipe)
        crafted_per = max(recipe.result_count, 1)
        batch_count = int(math.ceil(count / crafted_per))
        total: Dict[str, int] = {}
        next_chain = list(chain)
        next_chain.append(item_name)
        for req_item, req_count in requirements.items():
            needed = req_count * batch_count
            child = self._compute_transfer_requirements_from_inventory(
                req_item,
                needed,
                inventory_counts,
                available_for_choice,
                allow_smelting=allow_smelting,
                chain=next_chain,
            )
            self._merge_requirements(total, child)
        return total

    async def _transfer_needed_from_container(
        self,
        snapshot: ScreenSnapshot,
        needed: Dict[str, int],
        max_slots: int = 54,
        precise: bool = True,
        allow_smelting: bool = True,
        smelt_groups: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        if not needed:
            return {"ok": True, "actions": 0, "remaining": {}}
        if snapshot.cursor:
            cursor_actions, cursor_error = self._clear_cursor_actions(snapshot)
            if cursor_error:
                return {"ok": False, "error": cursor_error}
            if cursor_actions:
                ok = await self._send_sequence(cursor_actions)
                if not ok:
                    return {"ok": False, "error": "cursor_clear_failed"}
                raw = await self._get_snapshot(refresh=True)
                snapshot = ScreenSnapshot.from_dict(raw)
                if snapshot is None:
                    return {"ok": False, "error": "no_snapshot"}
        remaining = dict(needed)
        item_to_group: Dict[str, str] = {}
        group_items: Dict[str, List[str]] = {}
        group_remaining: Dict[str, int] = {}
        if isinstance(smelt_groups, dict):
            item_to_group = smelt_groups.get("item_to_group") or {}
            group_items = smelt_groups.get("group_items") or {}
            group_remaining = smelt_groups.get("group_remaining") or {}
        smelt_input_to_output: Dict[str, List[str]] = {}
        if allow_smelting:
            for output_item, inputs in SMELTING_OUTPUTS.items():
                for inp in inputs:
                    smelt_input_to_output.setdefault(inp, []).append(output_item)
        container_slots = [
            slot
            for slot in snapshot.slots
            if slot.group in {"container", "container_input", "container_output", "container_fuel"}
            and slot.item is not None
        ]
        if not precise:
            actions: List[Dict[str, Any]] = []
            for slot in container_slots[:max_slots]:
                item = slot.item
                if not item:
                    continue
                used_group = False
                used_smelt_output = False
                group_id = item_to_group.get(item.name)
                want = remaining.get(item.name, 0)
                if want <= 0 and allow_smelting:
                    for output_item in smelt_input_to_output.get(item.name, []):
                        if remaining.get(output_item, 0) > 0:
                            used_smelt_output = True
                            want = remaining.get(output_item, 0)
                            break
                if want <= 0 and group_id:
                    used_group = True
                    want = group_remaining.get(group_id, 0)
                if want <= 0:
                    continue
                actions.append({"type": "quickMove", "slot": slot.slot})
                moved = min(item.count, want)
                if used_group:
                    group_remaining[group_id] = max(0, want - moved)
                    for candidate in group_items.get(group_id, []):
                        remaining[candidate] = group_remaining[group_id]
                elif used_smelt_output:
                    for output_item in smelt_input_to_output.get(item.name, []):
                        if remaining.get(output_item, 0) > 0:
                            remaining[output_item] = max(0, want - moved)
                            break
                else:
                    remaining[item.name] = max(0, want - moved)
            ok = await self._send_sequence(actions)
            still_missing = {k: v for k, v in remaining.items() if v > 0}
            return {"ok": ok, "actions": len(actions), "remaining": still_missing}

        player_slots = self._build_player_slot_state(snapshot)
        actions = []
        processed = 0
        inventory_full = False
        for slot in container_slots:
            if processed >= max_slots:
                break
            item = slot.item
            if not item:
                continue
            used_group = False
            used_smelt_output = False
            group_id = item_to_group.get(item.name)
            want = remaining.get(item.name, 0)
            if want <= 0 and allow_smelting:
                for output_item in smelt_input_to_output.get(item.name, []):
                    if remaining.get(output_item, 0) > 0:
                        used_smelt_output = True
                        want = remaining.get(output_item, 0)
                        break
            if want <= 0 and group_id:
                used_group = True
                want = group_remaining.get(group_id, 0)
            if want <= 0:
                continue
            default_max = item.max_count if item.max_count > 0 else 64
            capacity = self._player_capacity_for_item(
                player_slots, item.name, default_max
            )
            if capacity <= 0:
                inventory_full = True
                break
            take = min(want, item.count, capacity)
            if take <= 0:
                continue
            actions.append(
                {"type": "clickSlot", "slot": slot.slot, "button": 0, "action": "pickup"}
            )
            remaining_to_place = take
            while remaining_to_place > 0:
                target = self._find_player_slot_for_item(
                    player_slots, item.name, default_max
                )
                if not target:
                    inventory_full = True
                    break
                if target["max_count"] <= 0:
                    target["max_count"] = default_max
                slot_capacity = max(0, target["max_count"] - target["count"])
                if slot_capacity <= 0:
                    target["count"] = target["max_count"]
                    continue
                place = min(remaining_to_place, slot_capacity)
                for _ in range(place):
                    actions.append(
                        {
                            "type": "clickSlot",
                            "slot": target["slot"],
                            "button": 1,
                            "action": "pickup",
                        }
                    )
                target["item"] = item.name
                target["count"] += place
                remaining_to_place -= place
            moved = take - remaining_to_place
            if item.count - moved > 0:
                actions.append(
                    {
                        "type": "clickSlot",
                        "slot": slot.slot,
                        "button": 0,
                        "action": "pickup",
                    }
                )
            if used_group:
                group_remaining[group_id] = max(0, want - moved)
                for candidate in group_items.get(group_id, []):
                    remaining[candidate] = group_remaining[group_id]
            elif used_smelt_output:
                for output_item in smelt_input_to_output.get(item.name, []):
                    if remaining.get(output_item, 0) > 0:
                        remaining[output_item] = max(0, want - moved)
                        break
            else:
                remaining[item.name] = max(0, want - moved)
            processed += 1
            if inventory_full:
                break
        ok = await self._send_sequence(actions)
        still_missing = {k: v for k, v in remaining.items() if v > 0}
        if inventory_full:
            return {
                "ok": False,
                "error": "inventory_full",
                "actions": len(actions),
                "remaining": still_missing,
            }
        return {"ok": ok, "actions": len(actions), "remaining": still_missing}

    def _is_utility_block_item(self, item_name: str) -> bool:
        return item_name in BASIC_UTILITY_BLOCKS

    def _build_craftable_catalog(self) -> Dict[str, Any]:
        if self._craftable_catalog is not None:
            return self._craftable_catalog
        recipe_book = self._get_recipe_book()
        craftables = recipe_book.craftable_items()
        categories: Dict[str, List[str]] = {
            "tools": [],
            "weapons": [],
            "armor": [],
            "containers": [],
            "utility_blocks": [],
            "materials": [],
            "crafting_table_only": [],
        }
        basic: set[str] = set()
        for item in craftables:
            if self._is_tool_item(item) or item in BASIC_TOOL_ITEMS:
                categories["tools"].append(item)
                basic.add(item)
            if self._is_weapon_item(item):
                categories["weapons"].append(item)
                basic.add(item)
            if _infer_armor_slot(item):
                categories["armor"].append(item)
                basic.add(item)
            if self._is_container_item(item):
                categories["containers"].append(item)
                basic.add(item)
            if self._is_utility_block_item(item):
                categories["utility_blocks"].append(item)
                basic.add(item)
            if item == "stick" or item == "torch" or self._is_planks(item):
                categories["materials"].append(item)
                basic.add(item)
            if item.endswith("_ingot"):
                categories["materials"].append(item)
                basic.add(item)
            if self._recipes_require_table(recipe_book.get_recipes(item)):
                categories["crafting_table_only"].append(item)
        for key, items in categories.items():
            categories[key] = sorted(set(items))
        basic_list = sorted(
            item
            for item in basic
            if not self._is_redstone_item(item) or self._is_container_item(item)
        )
        self._craftable_catalog = {
            "all": craftables,
            "categories": categories,
            "basic": basic_list,
        }
        return self._craftable_catalog

    async def run(self, skill: str, params: Dict[str, Any]) -> Dict[str, Any]:
        async with self._lock:
            name = (skill or "").strip().lower()
            if name in {"auto_equip", "equip"}:
                return await self.auto_equip()
            if name in {"auto_sort", "auto_sort_hotbar", "sort_hotbar"}:
                return await self.auto_sort_hotbar()
            if name in {"container_transfer", "transfer"}:
                return await self.container_transfer(params)
            if name in {"find_block", "findblock"}:
                return await self.find_block(params)
            if name in {"open_block"}:
                return await self.open_block(params)
            if name in {"set_debug", "debug"}:
                return await self.set_debug(params)
            if name in {"look_at", "lookat"}:
                return await self.look_at(params)
            if name in {"look_nearest_player", "look_player"}:
                return await self.look_at_nearest_player(params)
            if name in {"idle_look", "look_idle"}:
                return await self.idle_look(params)
            if name in {"autonomy_tick", "auto_tick"}:
                return await self.autonomy_tick(params)
            if name in {"go_to_position", "goto_position", "move_to"}:
                return await self.go_to_position(params)
            if name in {"go_to_nearest_block", "goto_block", "go_to_block"}:
                return await self.go_to_nearest_block(params)
            if name in {"go_to_player", "goto_player"}:
                return await self.go_to_player(params)
            if name in {"follow_player", "follow"}:
                return await self.follow_player(params)
            if name in {"attack_nearest", "attack"}:
                return await self.attack_nearest(params)
            if name in {"defend_self", "defend"}:
                return await self.defend_self(params)
            if name in {"smart_guard"}:
                return await self.smart_guard(params)
            if name in {"smart_gather"}:
                return await self.smart_gather(params)
            if name in {"pickup_nearby_items", "pickup_items"}:
                return await self.pickup_nearby_items(params)
            if name in {"collect_block", "collect"}:
                return await self.collect_block(params)
            if name in {"dig_area", "excavate", "dig_box"}:
                return await self.dig_area(params)
            if name in {"open_container", "open_chest"}:
                return await self.open_container(params)
            if name in {"place_block", "place"}:
                return await self.place_block(params)
            if name in {"pillar_up", "pillar", "pillarup"}:
                return await self.pillar_up(params)
            if name in {"open_crafting_table", "open_workbench", "open_table"}:
                return await self.open_crafting_table(params)
            if name in {"open_brewing_stand", "open_brew_stand", "open_brew"}:
                return await self.open_brewing_stand(params)
            if name in {"open_smithing_table", "open_smithing"}:
                return await self.open_smithing_table(params)
            if name in {"open_enchanting_table", "open_enchant"}:
                return await self.open_enchanting_table(params)
            if name in {"open_trade", "open_villager_trade", "open_merchant"}:
                return await self.open_trade(params)
            if name in {"view_container", "view_chest"}:
                return await self.view_container(params)
            if name in {"take_from_container", "take_from_chest", "loot_container"}:
                return await self.take_from_container(params)
            if name in {"craft_from_container", "auto_craft_container", "pickup_craft"}:
                return await self.craft_from_container(params)
            if name in {"craftable", "craftables", "craftable_catalog", "crafting_catalog"}:
                return await self.craftable_catalog(params)
            if name in {"craft", "auto_craft"}:
                return await self.craft_item(params)
            if name in {"smelt", "smelt_item", "smeltitem"}:
                return await self.smelt_item(params)
            if name in {"brew", "brew_item"}:
                return await self.brew_item(params)
            if name in {"smith", "smith_item"}:
                return await self.smith_item(params)
            if name in {"enchant", "enchant_item"}:
                return await self.enchant_item(params)
            if name in {"trade", "trade_item"}:
                return await self.trade_item(params)
            if name in {"plan", "plan_only", "planner"}:
                return await self.plan_actions(params, execute=False)
            if name in {"plan_execute", "plan_and_execute", "planrun"}:
                return await self.plan_actions(params, execute=True)
            if name in {"plan_execute_rules", "rule_plan_execute", "plan_rules"}:
                params = dict(params or {})
                params["planner_mode"] = "rules_only"
                return await self.plan_actions(params, execute=True)
            if name in {"cancel", "cancel_current", "abort"}:
                return await self.cancel_current()
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

    async def find_block(self, params: Dict[str, Any]) -> Dict[str, Any]:
        block = params.get("block")
        blocks = params.get("blocks")
        radius = int(params.get("radius", 8))
        max_results = int(params.get("max_results", 1))
        timeout = float(params.get("timeout", 2.0))
        targets: List[str] = []
        if isinstance(blocks, list):
            targets.extend([str(b) for b in blocks if b])
        if block:
            targets.append(str(block))
        result = await self._find_blocks(
            targets, radius=radius, max_results=max_results, timeout=timeout
        )
        return result

    async def open_block(self, params: Dict[str, Any]) -> Dict[str, Any]:
        block = params.get("block")
        blocks = params.get("blocks")
        radius = int(params.get("radius", 8))
        timeout = float(params.get("timeout", 4.0))
        move = bool(params.get("move", True))
        look_at = bool(params.get("look_at", True))
        look_duration_ms = int(params.get("look_duration_ms", 200))
        face = params.get("face", "up")
        targets: List[str] = []
        if isinstance(blocks, list):
            targets.extend([str(b) for b in blocks if b])
        if block:
            targets.append(str(block))
        if not targets:
            return {"ok": False, "error": "missing_block"}
        result = await self._find_blocks(targets, radius=radius, timeout=timeout)
        if not result.get("ok"):
            return result
        positions = result.get("positions")
        pos = None
        if isinstance(positions, list) and positions:
            pos = positions[0]
        # 可选：没有容器时放置一个箱子
        if pos is None and bool(params.get("place_if_missing", False)):
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot:
                chest_slot = next(
                    (
                        slot
                        for slot in snapshot.slots
                        if slot.item and slot.item.name in {"chest", "trapped_chest"}
                    ),
                    None,
                )
                if chest_slot is None:
                    craft_chest = await self.craft_item(
                        {
                            "item": "chest",
                            "count": 1,
                            "auto_open_table": True,
                            "recursive": True,
                        }
                    )
                    if craft_chest.get("ok"):
                        raw = await self._get_snapshot(refresh=True)
                        snapshot = ScreenSnapshot.from_dict(raw) or snapshot
                        chest_slot = next(
                            (
                                slot
                                for slot in snapshot.slots
                                if slot.item and slot.item.name in {"chest", "trapped_chest"}
                            ),
                            None,
                        )
                if chest_slot:
                    _, snapshot = await self._ensure_hotbar_slot_for_item(
                        snapshot, ["chest", "trapped_chest"]
                    )
                    placed = await self._place_block_from_hotbar(
                        snapshot, face=str(face), look_duration_ms=look_duration_ms
                    )
                    if placed:
                        await asyncio.sleep(0.4)
                        result_retry = await self._find_blocks(
                            targets, radius=radius, timeout=timeout
                        )
                        positions = result_retry.get("positions") if isinstance(result_retry, dict) else None
                        if isinstance(positions, list) and positions:
                            pos = positions[0]
        if pos is None:
            return {"ok": False, "error": "block_not_found"}
        pos = pos
        approach_distance = float(
            params.get("approach_distance", cfg.get("container_interact_distance", 2.0))
        )
        if move:
            moved = await self._move_near_position(
                pos,
                distance=approach_distance,
                timeout=timeout,
                horizontal_only=True,
            )
            if not moved:
                return {"ok": False, "error": "container_too_far", "position": pos}
        if look_at:
            await self._look_at_position(pos, duration_ms=look_duration_ms)
        used = await self._use_block_at(pos, face=str(face))
        if not used:
            return {"ok": False, "error": "use_block_failed", "position": pos}
        return {"ok": True, "position": pos}

    async def open_crafting_table(self, params: Dict[str, Any]) -> Dict[str, Any]:
        radius = int(params.get("radius", 8))
        timeout = float(params.get("timeout", 4.0))
        move = bool(params.get("move", True))
        look_at = bool(params.get("look_at", True))
        look_duration_ms = int(params.get("look_duration_ms", 200))
        face = params.get("face", "up")
        retries = max(1, int(params.get("retries", 3)))
        interaction_delay_ms = int(params.get("interaction_delay_ms", 120))
        faces = params.get("faces")
        if isinstance(faces, str):
            faces = [faces]
        if not isinstance(faces, list) or not faces:
            faces = [face, "north", "south", "west", "east", "up", "down"]
        faces = [str(f) for f in faces if f]
        result = await self._find_blocks([CRAFTING_TABLE_BLOCK], radius=radius, timeout=timeout)
        if not result.get("ok"):
            result = {"ok": False, "error": "crafting_table_not_found"}
        positions = result.get("positions")
        pos = None
        if isinstance(positions, list) and positions:
            pos = positions[0]
        # 如果附近没有工作台，尝试用 2x2 合成一个并放下
        if pos is None and bool(params.get("place_if_missing", True)):
            raw = await self._get_snapshot(refresh=True)
            snap = ScreenSnapshot.from_dict(raw)
            if snap and not self._inventory_has_item(snap, "crafting_table", 1):
                craft_table = await self.craft_item(
                    {
                        "item": "crafting_table",
                        "count": 1,
                        "auto_open_table": False,
                        "open_table": False,
                        "recursive": True,
                    }
                )
                if not craft_table.get("ok"):
                    return {
                        "ok": False,
                        "error": "crafting_table_not_found",
                        "detail": craft_table,
                    }
                raw = await self._get_snapshot(refresh=True)
                snap = ScreenSnapshot.from_dict(raw) or snap
            if snap:
                if not self._inventory_has_item(snap, "crafting_table", 1):
                    return {"ok": False, "error": "crafting_table_missing_after_craft"}
                _, snap = await self._ensure_hotbar_slot_for_item(
                    snap, ["crafting_table"]
                )
                placed = await self._place_block_from_hotbar(
                    snap, face=str(face), look_duration_ms=look_duration_ms
                )
                if placed:
                    await asyncio.sleep(0.5)
                    result_retry = await self._find_blocks(
                        [CRAFTING_TABLE_BLOCK], radius=radius, timeout=timeout
                    )
                    positions = result_retry.get("positions") if isinstance(result_retry, dict) else None
                    if isinstance(positions, list) and positions:
                        pos = positions[0]
            if pos is None:
                return {"ok": False, "error": "crafting_table_place_failed"}
        elif pos is None:
            return {"ok": False, "error": "crafting_table_not_found"}
        attempt_timeout = float(params.get("open_timeout", max(0.8, timeout / retries)))
        snapshot = await self._wait_for_crafting_table(timeout=0.1)
        if snapshot:
            return {"ok": True, "position": pos, "snapshot": snapshot, "already_open": True}
        max_reach = float(params.get("max_reach", 4.2))
        approach_distance = float(
            params.get(
                "approach_distance",
                self._headful_config().get("workstation_interact_distance", 2.0),
            )
        )
        await self._adapter.send_action({"type": "stopMove"}, self._headful_config())
        await self._adapter.send_action({"type": "stopInput"}, self._headful_config())
        for attempt in range(1, retries + 1):
            if move:
                moved = await self._move_near_position(
                    pos,
                    distance=approach_distance,
                    timeout=timeout,
                    horizontal_only=True,
                )
                if not moved:
                    self._debug_log("open_crafting_table too far", params)
                    continue
            current = self._player_pos()
            if current:
                try:
                    dx = float(current[0]) - float(pos.get("x"))
                    dz = float(current[2]) - float(pos.get("z"))
                    if dx * dx + dz * dz > max_reach * max_reach:
                        await self._adapter.send_action(
                            {"type": "move", "forward": 1.0, "durationMs": 300},
                            self._headful_config(),
                        )
                except (TypeError, ValueError):
                    pass
            if look_at:
                await self._look_at_position(pos, duration_ms=look_duration_ms)
            if interaction_delay_ms > 0:
                delay = max(interaction_delay_ms, look_duration_ms + 50)
                await asyncio.sleep(delay / 1000.0)
            for face_name in faces:
                used = await self._use_block_at(pos, str(face_name))
                if used:
                    snapshot = await self._wait_for_crafting_table(timeout=attempt_timeout)
                    if snapshot:
                        return {
                            "ok": True,
                            "position": pos,
                            "snapshot": snapshot,
                            "attempt": attempt,
                            "face": face_name,
                        }
            await self._adapter.send_action({"type": "useTarget"}, self._headful_config())
            snapshot = await self._wait_for_crafting_table(timeout=attempt_timeout)
            if snapshot:
                return {"ok": True, "position": pos, "snapshot": snapshot, "attempt": attempt}
            self._debug_log(f"open_crafting_table retry {attempt}/{retries} failed", params)
        return {"ok": False, "error": "crafting_table_open_failed", "position": pos}

    async def open_brewing_stand(self, params: Dict[str, Any]) -> Dict[str, Any]:
        radius = int(params.get("radius", 8))
        timeout = float(params.get("timeout", 4.0))
        move = bool(params.get("move", True))
        look_at = bool(params.get("look_at", True))
        look_duration_ms = int(params.get("look_duration_ms", 200))
        face = params.get("face", "up")
        retries = max(1, int(params.get("retries", 3)))
        cfg = self._headful_config()
        approach_distance = float(
            params.get("approach_distance", cfg.get("workstation_interact_distance", 2.0))
        )
        result = await self._find_blocks(["brewing_stand"], radius=radius, timeout=timeout)
        if not result.get("ok"):
            return {"ok": False, "error": "brewing_stand_not_found"}
        positions = result.get("positions")
        if not isinstance(positions, list) or not positions:
            return {"ok": False, "error": "brewing_stand_not_found"}
        pos = positions[0]
        snapshot = await self._wait_for_brewing_stand(timeout=0.1)
        if snapshot:
            return {"ok": True, "position": pos, "snapshot": snapshot, "already_open": True}
        attempt_timeout = float(params.get("open_timeout", max(0.8, timeout / retries)))
        await self._adapter.send_action({"type": "stopMove"}, self._headful_config())
        await self._adapter.send_action({"type": "stopInput"}, self._headful_config())
        for attempt in range(1, retries + 1):
            if move:
                moved = await self._move_near_position(
                    pos,
                    distance=approach_distance,
                    timeout=timeout,
                    horizontal_only=True,
                )
                if not moved:
                    self._debug_log("open_brewing_stand too far", params)
                    continue
            if look_at:
                await self._look_at_position(pos, duration_ms=look_duration_ms)
            used = await self._use_block_at(pos, str(face))
            if used:
                snapshot = await self._wait_for_brewing_stand(timeout=attempt_timeout)
                if snapshot:
                    return {
                        "ok": True,
                        "position": pos,
                        "snapshot": snapshot,
                        "attempt": attempt,
                    }
            await self._adapter.send_action({"type": "useTarget"}, self._headful_config())
            snapshot = await self._wait_for_brewing_stand(timeout=attempt_timeout)
            if snapshot:
                return {"ok": True, "position": pos, "snapshot": snapshot, "attempt": attempt}
        return {"ok": False, "error": "brewing_stand_open_failed", "position": pos}

    async def open_smithing_table(self, params: Dict[str, Any]) -> Dict[str, Any]:
        radius = int(params.get("radius", 8))
        timeout = float(params.get("timeout", 4.0))
        move = bool(params.get("move", True))
        look_at = bool(params.get("look_at", True))
        look_duration_ms = int(params.get("look_duration_ms", 200))
        face = params.get("face", "up")
        retries = max(1, int(params.get("retries", 3)))
        cfg = self._headful_config()
        approach_distance = float(
            params.get("approach_distance", cfg.get("workstation_interact_distance", 2.0))
        )
        result = await self._find_blocks(["smithing_table"], radius=radius, timeout=timeout)
        if not result.get("ok"):
            return {"ok": False, "error": "smithing_table_not_found"}
        positions = result.get("positions")
        if not isinstance(positions, list) or not positions:
            return {"ok": False, "error": "smithing_table_not_found"}
        pos = positions[0]
        snapshot = await self._wait_for_smithing_table(timeout=0.1)
        if snapshot:
            return {"ok": True, "position": pos, "snapshot": snapshot, "already_open": True}
        attempt_timeout = float(params.get("open_timeout", max(0.8, timeout / retries)))
        await self._adapter.send_action({"type": "stopMove"}, self._headful_config())
        await self._adapter.send_action({"type": "stopInput"}, self._headful_config())
        for attempt in range(1, retries + 1):
            if move:
                moved = await self._move_near_position(
                    pos,
                    distance=approach_distance,
                    timeout=timeout,
                    horizontal_only=True,
                )
                if not moved:
                    self._debug_log("open_smithing_table too far", params)
                    continue
            if look_at:
                await self._look_at_position(pos, duration_ms=look_duration_ms)
            used = await self._use_block_at(pos, str(face))
            if used:
                snapshot = await self._wait_for_smithing_table(timeout=attempt_timeout)
                if snapshot:
                    return {
                        "ok": True,
                        "position": pos,
                        "snapshot": snapshot,
                        "attempt": attempt,
                    }
            await self._adapter.send_action({"type": "useTarget"}, self._headful_config())
            snapshot = await self._wait_for_smithing_table(timeout=attempt_timeout)
            if snapshot:
                return {"ok": True, "position": pos, "snapshot": snapshot, "attempt": attempt}
        return {"ok": False, "error": "smithing_table_open_failed", "position": pos}

    async def open_enchanting_table(self, params: Dict[str, Any]) -> Dict[str, Any]:
        radius = int(params.get("radius", 8))
        timeout = float(params.get("timeout", 4.0))
        move = bool(params.get("move", True))
        look_at = bool(params.get("look_at", True))
        look_duration_ms = int(params.get("look_duration_ms", 200))
        face = params.get("face", "up")
        retries = max(1, int(params.get("retries", 3)))
        cfg = self._headful_config()
        approach_distance = float(
            params.get("approach_distance", cfg.get("workstation_interact_distance", 2.0))
        )
        result = await self._find_blocks(["enchanting_table"], radius=radius, timeout=timeout)
        if not result.get("ok"):
            return {"ok": False, "error": "enchanting_table_not_found"}
        positions = result.get("positions")
        if not isinstance(positions, list) or not positions:
            return {"ok": False, "error": "enchanting_table_not_found"}
        pos = positions[0]
        snapshot = await self._wait_for_enchanting_table(timeout=0.1)
        if snapshot:
            return {"ok": True, "position": pos, "snapshot": snapshot, "already_open": True}
        attempt_timeout = float(params.get("open_timeout", max(0.8, timeout / retries)))
        await self._adapter.send_action({"type": "stopMove"}, self._headful_config())
        await self._adapter.send_action({"type": "stopInput"}, self._headful_config())
        for attempt in range(1, retries + 1):
            if move:
                moved = await self._move_near_position(
                    pos,
                    distance=approach_distance,
                    timeout=timeout,
                    horizontal_only=True,
                )
                if not moved:
                    self._debug_log("open_enchanting_table too far", params)
                    continue
            if look_at:
                await self._look_at_position(pos, duration_ms=look_duration_ms)
            used = await self._use_block_at(pos, str(face))
            if used:
                snapshot = await self._wait_for_enchanting_table(timeout=attempt_timeout)
                if snapshot:
                    return {
                        "ok": True,
                        "position": pos,
                        "snapshot": snapshot,
                        "attempt": attempt,
                    }
            await self._adapter.send_action({"type": "useTarget"}, self._headful_config())
            snapshot = await self._wait_for_enchanting_table(timeout=attempt_timeout)
            if snapshot:
                return {"ok": True, "position": pos, "snapshot": snapshot, "attempt": attempt}
        return {"ok": False, "error": "enchanting_table_open_failed", "position": pos}

    async def open_trade(self, params: Dict[str, Any]) -> Dict[str, Any]:
        radius = float(params.get("radius", params.get("range", 6.0)))
        timeout = float(params.get("timeout", 4.0))
        move = bool(params.get("move", True))
        look_at = bool(params.get("look_at", True))
        look_duration_ms = int(params.get("look_duration_ms", 200))
        retries = max(1, int(params.get("retries", 3)))
        entity = self._select_nearest_entity(
            target_type="minecraft:villager", max_distance=radius
        )
        if entity is None:
            entity = self._select_nearest_entity(
                target_type="minecraft:wandering_trader", max_distance=radius
            )
        if entity is None:
            return {"ok": False, "error": "trader_not_found"}
        snapshot = await self._wait_for_trade_screen(timeout=0.1)
        if snapshot:
            return {"ok": True, "entity": entity, "snapshot": snapshot, "already_open": True}
        attempt_timeout = float(params.get("open_timeout", max(0.8, timeout / retries)))
        await self._adapter.send_action({"type": "stopMove"}, self._headful_config())
        await self._adapter.send_action({"type": "stopInput"}, self._headful_config())
        for attempt in range(1, retries + 1):
            if move:
                await self._move_near_position(entity, distance=2.5, timeout=timeout)
            if look_at:
                await self._look_at_position(entity, duration_ms=look_duration_ms)
            await self._adapter.send_action({"type": "useTarget"}, self._headful_config())
            snapshot = await self._wait_for_trade_screen(timeout=attempt_timeout)
            if snapshot:
                return {
                    "ok": True,
                    "entity": entity,
                    "snapshot": snapshot,
                    "attempt": attempt,
                }
        return {"ok": False, "error": "trade_open_failed", "entity": entity}

    async def open_furnace(self, params: Dict[str, Any]) -> Dict[str, Any]:
        radius = int(params.get("radius", 8))
        timeout = float(params.get("timeout", 4.0))
        move = bool(params.get("move", True))
        look_at = bool(params.get("look_at", True))
        look_duration_ms = int(params.get("look_duration_ms", 200))
        face = params.get("face", "up")
        retries = max(1, int(params.get("retries", 3)))
        cfg = self._headful_config()
        approach_distance = float(
            params.get("approach_distance", cfg.get("workstation_interact_distance", 2.0))
        )
        blocks = params.get("blocks")
        block = params.get("block")
        targets: List[str] = []
        if isinstance(blocks, list):
            targets.extend([str(b) for b in blocks if b])
        if block:
            targets.append(str(block))
        if not targets:
            targets = list(SMELTING_BLOCKS)
        result = await self._find_blocks(targets, radius=radius, timeout=timeout)
        if not result.get("ok"):
            result = {"ok": False, "error": "smelting_block_not_found"}
        positions = result.get("positions")
        pos = None
        if isinstance(positions, list) and positions:
            pos = positions[0]
        # 如果附近没有熔炉类方块，尝试放置一个（使用手上/背包里的 furnace/blast_furnace/smoker）
        if pos is None:
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot:
                # 尝试从附近容器/背包取出已有的炉子（不强制合成）
                inv_counts = self._inventory_counts(snapshot)
                if inv_counts.get("furnace", 0) + inv_counts.get("blast_furnace", 0) + inv_counts.get("smoker", 0) <= 0 and bool(
                    params.get("take_furnace_from_containers", True)
                ):
                    for target in ("furnace", "blast_furnace", "smoker"):
                        take_result = await self.craft_from_container(
                            {
                                "item": target,
                                "count": 1,
                                "skip_craft": True,
                                "open_table": False,
                                "smart_pickup": True,
                                "precise_pickup": True,
                                "multi_container": True,
                                "use_llm_orchestrator": False,
                                "_no_llm_orchestrator": True,
                            }
                        )
                        if take_result.get("ok"):
                            raw = await self._get_snapshot(refresh=True)
                            snapshot = ScreenSnapshot.from_dict(raw) or snapshot
                            inv_counts = self._inventory_counts(snapshot)
                            break
                # 先找现成的炉子
                furnace_slot = next(
                    (
                        slot
                        for slot in snapshot.slots
                        if slot.item
                        and slot.item.name in {"furnace", "blast_furnace", "smoker"}
                    ),
                    None,
                )
                # 没有的话尝试合成一个（需要工作台，依赖前面 open_crafting_table 可自放置）
                if furnace_slot is None and bool(params.get("craft_if_missing", True)):
                    if not self._inventory_has_item(snapshot, "furnace", 1):
                        craft_furnace = await self.craft_item(
                            {
                                "item": "furnace",
                                "count": 1,
                                "auto_open_table": True,
                                "recursive": True,
                            }
                        )
                        if not craft_furnace.get("ok"):
                            return {
                                "ok": False,
                                "error": "furnace_craft_failed",
                                "detail": craft_furnace,
                            }
                        raw = await self._get_snapshot(refresh=True)
                        snapshot = ScreenSnapshot.from_dict(raw) or snapshot
                    furnace_slot = next(
                        (
                            slot
                            for slot in snapshot.slots
                            if slot.item
                            and slot.item.name in {"furnace", "blast_furnace", "smoker"}
                        ),
                        None,
                    )
                if furnace_slot:
                    _, snapshot = await self._ensure_hotbar_slot_for_item(
                        snapshot, ["furnace", "blast_furnace", "smoker"]
                    )
                    placed = await self._place_block_from_hotbar(
                        snapshot, face=str(face), look_duration_ms=look_duration_ms
                    )
                    if placed:
                        await asyncio.sleep(0.5)
                        raw_place = await self._get_snapshot(refresh=True)
                        snap_place = ScreenSnapshot.from_dict(raw_place)
                        if snap_place and self._snapshot_has_smelting_container(snap_place):
                            return {
                                "ok": True,
                                "position": self._player_pos() or {"x": 0, "y": 0, "z": 0},
                                "snapshot": snap_place,
                                "placed": True,
                            }
                        # 重新找一下（可能方块放下了但界面没开）
                        result = await self._find_blocks(
                            targets, radius=radius, timeout=timeout
                        )
                        positions = result.get("positions")
                        if isinstance(positions, list) and positions:
                            pos = positions[0]
                    else:
                        return {"ok": False, "error": "furnace_place_failed"}
            if pos is None:
                return {"ok": False, "error": "smelting_block_not_found"}
        attempt_timeout = float(params.get("open_timeout", max(0.8, timeout / retries)))
        snapshot = await self._wait_for_smelting_container(timeout=0.1)
        if snapshot:
            return {"ok": True, "position": pos, "snapshot": snapshot, "already_open": True}
        await self._adapter.send_action({"type": "stopMove"}, self._headful_config())
        await self._adapter.send_action({"type": "stopInput"}, self._headful_config())
        for attempt in range(1, retries + 1):
            if move:
                moved = await self._move_near_position(
                    pos,
                    distance=approach_distance,
                    timeout=timeout,
                    horizontal_only=True,
                )
                if not moved:
                    self._debug_log("open_furnace too far", params)
                    continue
            if look_at:
                await self._look_at_position(pos, duration_ms=look_duration_ms)
            used = await self._use_block_at(pos, str(face))
            if used:
                snapshot = await self._wait_for_smelting_container(timeout=attempt_timeout)
                if snapshot:
                    return {
                        "ok": True,
                        "position": pos,
                        "snapshot": snapshot,
                        "attempt": attempt,
                    }
            await self._adapter.send_action({"type": "useTarget"}, self._headful_config())
            snapshot = await self._wait_for_smelting_container(timeout=attempt_timeout)
            if snapshot:
                return {"ok": True, "position": pos, "snapshot": snapshot, "attempt": attempt}
        return {"ok": False, "error": "smelting_block_open_failed", "position": pos}

    async def open_container(self, params: Dict[str, Any]) -> Dict[str, Any]:
        block = params.get("block")
        blocks = params.get("blocks")
        position = params.get("position")
        radius = int(params.get("radius", 8))
        timeout = float(params.get("timeout", 4.0))
        move = bool(params.get("move", True))
        look_at = bool(params.get("look_at", True))
        look_duration_ms = int(params.get("look_duration_ms", 200))
        face = params.get("face", "up")
        cfg = self._headful_config()
        approach_distance = float(
            params.get("approach_distance", cfg.get("container_interact_distance", 2.0))
        )
        deny_raw = params.get("container_denylist", cfg.get("container_denylist"))
        if deny_raw is None:
            deny_raw = ["ender_chest"]
        if isinstance(deny_raw, str):
            deny_list = [deny_raw]
        elif isinstance(deny_raw, list):
            deny_list = [str(item) for item in deny_raw if item]
        else:
            deny_list = []
        deny_set = {self._normalize_block_name(item).split(":", 1)[1] for item in deny_list}
        settle_ms = int(params.get("container_settle_ms", params.get("settle_ms", cfg.get("container_settle_ms", 400))))
        ensure_closed = bool(params.get("ensure_closed", True))
        close_timeout_ms = int(params.get("close_timeout_ms", cfg.get("screen_close_timeout_ms", 800)))
        targets: List[str] = []
        if isinstance(blocks, list):
            targets.extend([str(b) for b in blocks if b])
        if block:
            targets.append(str(block))
        if ensure_closed:
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot and snapshot.screen_open:
                await self._adapter.send_action(
                    {"type": "closeScreen"}, self._headful_config()
                )
                await self._wait_for_screen_closed(timeout=close_timeout_ms / 1000.0)
        if position:
            pos = position
            if deny_set and isinstance(pos, dict):
                block_name = str(pos.get("block", ""))
                if block_name and block_name.split(":", 1)[-1] in deny_set:
                    return {"ok": False, "error": "container_denied"}
        else:
            if not targets:
                targets = list(CONTAINER_BLOCKS)
            if deny_set:
                targets = [
                    t
                    for t in targets
                    if self._normalize_block_name(t).split(":", 1)[1] not in deny_set
                ]
                if not targets:
                    return {"ok": False, "error": "container_denied"}
            result = await self._find_blocks(targets, radius=radius, timeout=timeout)
            if not result.get("ok"):
                return result
            positions = result.get("positions")
            if not isinstance(positions, list) or not positions:
                return {"ok": False, "error": "container_not_found"}
            pos = positions[0]
            if deny_set and isinstance(pos, dict):
                block_name = str(pos.get("block", ""))
                if block_name and block_name.split(":", 1)[-1] in deny_set:
                    return {"ok": False, "error": "container_denied"}
        if move:
            moved = await self._move_near_position(
                pos,
                distance=approach_distance,
                timeout=timeout,
                horizontal_only=True,
            )
            if not moved:
                return {"ok": False, "error": "container_too_far", "position": pos}
        if look_at:
            await self._look_at_position(pos, duration_ms=look_duration_ms)
        used = await self._use_block_at(pos, str(face))
        if not used:
            return {"ok": False, "error": "use_block_failed", "position": pos}
        snapshot = await self._wait_for_container(timeout=timeout)
        if not snapshot:
            return {"ok": False, "error": "container_open_failed", "position": pos}
        snapshot = await self._stabilize_container_snapshot(snapshot, settle_ms)
        await self._update_container_registry(pos, snapshot)
        return {"ok": True, "position": pos, "snapshot": snapshot}

    async def place_block(self, params: Dict[str, Any]) -> Dict[str, Any]:
        block = _normalize_item_name(params.get("block") or params.get("item"))
        face = params.get("face", "up")
        if not block:
            return {"ok": False, "error": "missing_block"}
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        if snapshot is None:
            return {"ok": False, "error": "no_snapshot"}
        if not self._inventory_has_item(snapshot, block, 1):
            return {"ok": False, "error": "missing_item", "item": block}
        _, snapshot = await self._ensure_hotbar_slot_for_item(snapshot, [block])
        placed = await self._place_block_from_hotbar(snapshot, face=str(face))
        return {"ok": bool(placed), "block": block}

    def _candidate_pillar_blocks(self, snapshot: ScreenSnapshot) -> List[str]:
        candidates = list(PILLAR_BLOCK_PREFERRED)
        for slot in snapshot.slots:
            if slot.item is None:
                continue
            name = slot.item.name
            if self._is_planks(name) or self._is_log(name):
                if name not in candidates:
                    candidates.append(name)
        return candidates

    async def pillar_up(self, params: Dict[str, Any]) -> Dict[str, Any]:
        steps_raw = params.get("steps") or params.get("count") or 1
        delay_raw = params.get("delay_ms") or params.get("delayMs") or 320
        try:
            steps = max(1, min(int(steps_raw), 8))
        except (TypeError, ValueError):
            steps = 1
        try:
            delay_ms = max(220, int(delay_raw))
        except (TypeError, ValueError):
            delay_ms = 320
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        if snapshot is None:
            return {"ok": False, "error": "no_snapshot"}
        candidates = self._candidate_pillar_blocks(snapshot)
        hotbar_index, snapshot = await self._ensure_hotbar_slot_for_item(snapshot, candidates)
        if hotbar_index is None:
            return {"ok": False, "error": "missing_block"}
        ok = await self._adapter.send_action(
            {"type": "pillarUp", "steps": steps, "delayMs": delay_ms},
            self._headful_config(),
        )
        return {"ok": ok, "steps": steps, "delay_ms": delay_ms}

    async def set_debug(self, params: Dict[str, Any]) -> Dict[str, Any]:
        enabled = bool(params.get("enabled", True))
        chat = bool(params.get("chat", False))
        ok = await self._adapter.send_action(
            {"type": "setDebug", "enabled": enabled, "chat": chat},
            self._headful_config(),
        )
        return {"ok": ok, "enabled": enabled, "chat": chat}

    async def look_at(self, params: Dict[str, Any]) -> Dict[str, Any]:
        entity_id = params.get("entity_id")
        entity_type = params.get("entity_type")
        entity_name = params.get("entity_name")
        duration_ms = int(params.get("duration_ms", 200))
        pos = params.get("position")
        if pos is None and entity_id is not None:
            for entity in self._nearby_entities():
                if int(entity.get("id", -1)) == int(entity_id):
                    pos = entity
                    break
        if pos is None and (entity_type or entity_name):
            selected = self._select_nearest_entity(
                target_type=entity_type, target_name=entity_name
            )
            if selected is None:
                return {"ok": False, "error": "entity_not_found"}
            pos = selected
        if pos is None:
            return {"ok": False, "error": "missing_position"}
        ok = await self._look_at_position(pos, duration_ms=duration_ms)
        return {"ok": ok, "position": pos}

    async def look_at_nearest_player(self, params: Dict[str, Any]) -> Dict[str, Any]:
        name = params.get("player_name") or params.get("player") or params.get("name")
        max_distance = float(params.get("max_distance", params.get("range", 12.0)))
        duration_ms = int(params.get("duration_ms", 200))
        entity = self._select_nearest_entity(
            target_type="minecraft:player", target_name=name, max_distance=max_distance
        )
        if entity is None:
            return {"ok": False, "error": "player_not_found"}
        ok = await self._look_at_position(entity, duration_ms=duration_ms)
        return {"ok": ok, "entity": entity}

    async def idle_look(self, params: Dict[str, Any]) -> Dict[str, Any]:
        yaw_pitch = self._player_yaw_pitch()
        if not yaw_pitch:
            return {"ok": False, "error": "no_orientation"}
        yaw, pitch = yaw_pitch
        yaw_delta = float(params.get("yaw_delta", 24.0))
        pitch_delta = float(params.get("pitch_delta", 8.0))
        duration_ms = int(params.get("duration_ms", 200))
        target_yaw = (yaw + random.uniform(-yaw_delta, yaw_delta)) % 360.0
        target_pitch = max(min(pitch + random.uniform(-pitch_delta, pitch_delta), 35.0), -35.0)
        await self._adapter.send_action(
            {
                "type": "lookSmooth",
                "yaw": target_yaw,
                "pitch": target_pitch,
                "durationMs": duration_ms,
            },
            self._headful_config(),
        )
        return {"ok": True, "yaw": target_yaw, "pitch": target_pitch}

    async def autonomy_tick(self, params: Dict[str, Any]) -> Dict[str, Any]:
        cfg = self._headful_config()
        if not bool(cfg.get("autonomy_enabled", False)):
            return {"ok": False, "error": "autonomy_disabled"}
        last_screen = getattr(self._adapter, "last_screen", None)
        if isinstance(last_screen, dict) and last_screen.get("screenOpen"):
            return {"ok": False, "error": "screen_open"}
        now = time.time()

        guard_enabled = bool(cfg.get("autonomy_guard", cfg.get("enable_smart_guard", True)))
        guard_interval = float(cfg.get("autonomy_guard_interval_sec", 2.0))
        guard_range = float(cfg.get("autonomy_guard_range", 12.0))
        if guard_enabled and now - self._autonomy_last_guard >= guard_interval:
            threat = self._select_nearest_hostile_entity(
                max_distance_sq=guard_range * guard_range
            )
            if threat:
                self._autonomy_last_guard = now
                etype = str(threat.get("type", "")).split(":")[-1]
                result = await self.attack_nearest(
                    {
                        "entity_type": etype,
                        "duration_sec": params.get("guard_duration_sec", 6.0),
                        "range": guard_range,
                    }
                )
                result["action"] = "guard"
                return result

        gather_enabled = bool(cfg.get("autonomy_gather", cfg.get("enable_smart_gather", True)))
        gather_interval = float(cfg.get("autonomy_gather_interval_sec", 18.0))
        harvest_enabled = bool(cfg.get("autonomy_harvest_crops", True))
        harvest_interval = float(cfg.get("autonomy_harvest_interval_sec", 10.0))
        if harvest_enabled and now - self._autonomy_last_crop >= harvest_interval:
            self._autonomy_last_crop = now
            result = await self._harvest_nearby_crops(
                {
                    "radius": params.get("crop_radius", 6),
                    "max_results": params.get("crop_max", 2),
                    "timeout": params.get("crop_timeout", 4.0),
                    "mature_only": cfg.get("autonomy_harvest_mature_only", True),
                }
            )
            if result.get("ok"):
                result["action"] = "harvest_crops"
                return result
        if gather_enabled and now - self._autonomy_last_gather >= gather_interval:
            self._autonomy_last_gather = now
            result = await self.smart_gather(
                {
                    "range": params.get("gather_range", 8.0),
                    "timeout": params.get("gather_timeout", 6.0),
                }
            )
            result["action"] = "gather"
            return result

        look_enabled = bool(cfg.get("autonomy_look_players", True))
        look_interval = float(cfg.get("autonomy_look_interval_sec", 3.0))
        look_range = float(cfg.get("autonomy_look_range", 12.0))
        if look_enabled and now - self._autonomy_last_look >= look_interval:
            player_name = params.get("player") or params.get("player_name") or params.get("name")
            entity = self._select_nearest_entity(
                target_type="minecraft:player",
                target_name=player_name,
                max_distance=look_range,
            )
            if entity:
                self._autonomy_last_look = now
                ok = await self._look_at_position(
                    entity, duration_ms=int(params.get("look_duration_ms", 200))
                )
                return {"ok": ok, "action": "look_player", "entity": entity}

        patrol_enabled = bool(cfg.get("autonomy_patrol", True))
        patrol_interval = float(cfg.get("autonomy_patrol_interval_sec", 8.0))
        if patrol_enabled and now - self._autonomy_last_patrol >= patrol_interval:
            self._autonomy_last_patrol = now
            origin = self._player_pos()
            if origin:
                radius = float(cfg.get("autonomy_patrol_radius", 4.0))
                distance = float(cfg.get("autonomy_patrol_distance", 2.5))
                timeout = float(cfg.get("autonomy_patrol_timeout", 4.0))
                angle = random.uniform(0.0, math.tau)
                step = random.uniform(max(1.0, radius * 0.4), radius)
                target = {
                    "x": origin[0] + math.cos(angle) * step,
                    "y": origin[1],
                    "z": origin[2] + math.sin(angle) * step,
                }
                ok = await self._move_near_position(
                    target, distance=distance, timeout=timeout
                )
                return {"ok": ok, "action": "patrol", "target": target}

        idle_enabled = bool(cfg.get("autonomy_idle_look", True))
        idle_interval = float(cfg.get("autonomy_idle_interval_sec", 6.0))
        if idle_enabled and now - self._autonomy_last_idle >= idle_interval:
            self._autonomy_last_idle = now
            result = await self.idle_look(
                {
                    "yaw_delta": params.get("idle_yaw_delta", 20.0),
                    "pitch_delta": params.get("idle_pitch_delta", 6.0),
                    "duration_ms": params.get("idle_duration_ms", 200),
                }
            )
            result["action"] = "idle_look"
            return result

        return {"ok": True, "action": "idle"}

    async def go_to_position(self, params: Dict[str, Any]) -> Dict[str, Any]:
        pos = params.get("position") or {
            "x": params.get("x"),
            "y": params.get("y"),
            "z": params.get("z"),
        }
        distance = float(params.get("distance", 3.5))
        timeout = float(params.get("timeout", 6.0))
        if not isinstance(pos, dict):
            return {"ok": False, "error": "missing_position"}
        ok = await self._move_near_position(pos, distance=distance, timeout=timeout)
        return {"ok": ok, "position": pos}

    async def go_to_nearest_block(self, params: Dict[str, Any]) -> Dict[str, Any]:
        block = params.get("block")
        blocks = params.get("blocks")
        radius = int(params.get("radius", 16))
        timeout = float(params.get("timeout", 6.0))
        distance = float(params.get("distance", 3.5))
        look_at = bool(params.get("look_at", True))
        look_duration_ms = int(params.get("look_duration_ms", 200))
        targets: List[str] = []
        if isinstance(blocks, list):
            targets.extend([str(b) for b in blocks if b])
        if block:
            targets.append(str(block))
        if not targets:
            return {"ok": False, "error": "missing_block"}
        result = await self._find_blocks(targets, radius=radius, timeout=timeout)
        if not result.get("ok"):
            return result
        positions = result.get("positions")
        if not isinstance(positions, list) or not positions:
            return {"ok": False, "error": "block_not_found"}
        pos = positions[0]
        ok = await self._move_near_position(pos, distance=distance, timeout=timeout)
        if look_at:
            await self._look_at_position(pos, duration_ms=look_duration_ms)
        return {"ok": ok, "position": pos}

    async def go_to_player(self, params: Dict[str, Any]) -> Dict[str, Any]:
        name = params.get("player_name")
        distance = float(params.get("distance", 3.0))
        timeout = float(params.get("timeout", 6.0))
        entity = self._select_nearest_entity(
            target_type="minecraft:player", target_name=name
        )
        if entity is None:
            return {"ok": False, "error": "player_not_found"}
        ok = await self._move_near_position(entity, distance=distance, timeout=timeout)
        return {"ok": ok, "entity": entity}

    async def follow_player(self, params: Dict[str, Any]) -> Dict[str, Any]:
        name = params.get("player_name")
        duration_sec = float(params.get("duration_sec", 12.0))
        interval_sec = float(params.get("interval_sec", 1.2))
        distance = float(params.get("distance", 3.0))
        timeout = float(params.get("timeout", 4.0))
        start = time.time()
        steps = 0
        last_entity: Optional[Dict[str, Any]] = None
        while time.time() - start < duration_sec:
            entity = self._select_nearest_entity(
                target_type="minecraft:player", target_name=name
            )
            if entity is None:
                break
            last_entity = entity
            await self._move_near_position(entity, distance=distance, timeout=timeout)
            steps += 1
            await asyncio.sleep(interval_sec)
        return {
            "ok": last_entity is not None,
            "steps": steps,
            "entity": last_entity,
        }

    async def attack_nearest(self, params: Dict[str, Any]) -> Dict[str, Any]:
        entity_type = params.get("entity_type") or params.get("type")
        if not entity_type:
            return {"ok": False, "error": "missing_entity_type"}
        max_distance = float(params.get("range", params.get("distance", 24.0)))
        attack_distance = float(params.get("attack_distance", 3.0))
        timeout = float(params.get("timeout", 6.0))
        duration_sec = float(params.get("duration_sec", 6.0))
        interval_sec = float(params.get("interval_sec", 0.6))
        entity = self._select_nearest_entity(
            target_type=str(entity_type), max_distance=max_distance
        )
        if entity is None:
            return {"ok": False, "error": "entity_not_found"}
        await self._move_near_position(entity, distance=attack_distance, timeout=timeout)
        await self._look_at_position(entity, duration_ms=200)
        start = time.time()
        hits = 0
        while time.time() - start < duration_sec:
            await self._adapter.send_action(
                {"type": "attack", "entityId": int(entity.get("id", -1))},
                self._headful_config(),
            )
            hits += 1
            await asyncio.sleep(interval_sec)
            refreshed = None
            for candidate in self._nearby_entities():
                if int(candidate.get("id", -1)) == int(entity.get("id", -2)):
                    refreshed = candidate
                    break
            if refreshed is None:
                break
            entity = refreshed
        return {"ok": True, "hits": hits, "entity": entity}

    async def defend_self(self, params: Dict[str, Any]) -> Dict[str, Any]:
        max_distance = float(params.get("range", params.get("distance", 12.0)))
        duration_sec = float(params.get("duration_sec", 12.0))
        start = time.time()
        kills = 0
        last = None
        while time.time() - start < duration_sec:
            entity = None
            for candidate in self._nearby_entities():
                if not candidate.get("type"):
                    continue
                entity_type = str(candidate.get("type", "")).split(":")[-1]
                if entity_type not in HOSTILE_ENTITY_TYPES:
                    continue
                if float(candidate.get("dist", 1e9)) > max_distance * max_distance:
                    continue
                entity = candidate
                break
            if entity is None:
                break
            last = entity
            await self.attack_nearest(
                {
                    "entity_type": str(entity.get("type", "")),
                    "duration_sec": 4.0,
                    "range": max_distance,
                }
            )
            kills += 1
            await asyncio.sleep(0.4)
        return {"ok": last is not None, "kills": kills, "last": last}

    async def pickup_nearby_items(self, params: Dict[str, Any]) -> Dict[str, Any]:
        max_distance = float(params.get("range", params.get("distance", 12.0)))
        timeout = float(params.get("timeout", 4.0))
        moved = 0
        items = [
            e
            for e in self._nearby_entities()
            if self._match_entity_type(e, "minecraft:item")
            and float(e.get("dist", 1e9)) <= max_distance * max_distance
        ]
        items.sort(key=lambda e: float(e.get("dist", 1e9)))
        for entity in items:
            await self._move_near_position(entity, distance=1.5, timeout=timeout)
            moved += 1
            await asyncio.sleep(0.3)
        return {"ok": moved > 0, "moved": moved}

    async def collect_block(self, params: Dict[str, Any]) -> Dict[str, Any]:
        block = params.get("block")
        blocks_raw = params.get("blocks")
        targets: List[str] = []
        if block:
            targets.append(str(block))
        if isinstance(blocks_raw, list):
            targets.extend([str(b) for b in blocks_raw if b])
        if not targets:
            return {"ok": False, "error": "missing_block"}
        count = int(params.get("count", 1))
        radius = int(params.get("radius", 16))
        timeout = float(params.get("timeout", 6.0))
        attack_ms = int(params.get("attack_ms", 1200))
        distance = float(params.get("distance", 3.5))
        look_at = bool(params.get("look_at", True))
        auto_equip = bool(params.get("auto_equip_tool", params.get("equip_tool", True)))
        if auto_equip:
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot is not None:
                tool_type = self._tool_type_for_blocks(targets)
                if tool_type:
                    tool_name = self._best_tool_name(snapshot, tool_type)
                    if tool_name:
                        await self._ensure_hotbar_slot_for_item(snapshot, [tool_name])
                        self._log_append(f"[tool] equip {tool_name} for {tool_type}")
                    else:
                        self._log_append(f"[tool] missing {tool_type} for {targets}")
        positions = []
        find_result = await self._find_blocks(
            targets,
            radius=radius,
            max_results=max(count, 1),
            timeout=timeout,
        )
        if find_result.get("ok"):
            positions = [
                pos for pos in (find_result.get("positions") or []) if isinstance(pos, dict)
            ]
        if not positions:
            return {"ok": False, "error": "block_not_found"}
        broken = 0
        for pos in positions:
            if broken >= count:
                break
            await self._move_near_position(pos, distance=distance, timeout=timeout)
            if look_at:
                await self._look_at_position(pos, duration_ms=200)
            await self._adapter.send_action(
                {"type": "setKey", "key": "attack", "pressed": True},
                self._headful_config(),
            )
            await asyncio.sleep(max(0.2, attack_ms / 1000.0))
            await self._adapter.send_action(
                {"type": "setKey", "key": "attack", "pressed": False},
                self._headful_config(),
            )
            broken += 1
            await asyncio.sleep(0.3)
        return {"ok": broken > 0, "broken": broken, "blocks": targets}

    async def _move_near_block_target(
        self,
        pos: Dict[str, Any],
        distance: float,
        timeout: float,
    ) -> bool:
        try:
            x = float(pos.get("x"))
            y = float(pos.get("y"))
            z = float(pos.get("z"))
        except (TypeError, ValueError, AttributeError):
            return False
        candidates = [
            {"x": x, "y": y + 1, "z": z},
            {"x": x + 1, "y": y, "z": z},
            {"x": x - 1, "y": y, "z": z},
            {"x": x, "y": y, "z": z + 1},
            {"x": x, "y": y, "z": z - 1},
        ]
        for candidate in candidates:
            moved = await self._move_near_position(
                candidate,
                distance=distance,
                timeout=timeout,
                horizontal_only=True,
            )
            if moved:
                return True
        return False

    async def _dig_block_at(
        self,
        pos: Dict[str, Any],
        attack_ms: int,
        distance: float,
        timeout: float,
        look_duration_ms: int,
    ) -> bool:
        moved = await self._move_near_block_target(pos, distance=distance, timeout=timeout)
        if not moved:
            return False
        if look_duration_ms > 0:
            await self._look_at_position(pos, duration_ms=look_duration_ms)
        await self._adapter.send_action(
            {"type": "setKey", "key": "attack", "pressed": True},
            self._headful_config(),
        )
        await asyncio.sleep(max(0.2, attack_ms / 1000.0))
        await self._adapter.send_action(
            {"type": "setKey", "key": "attack", "pressed": False},
            self._headful_config(),
        )
        await asyncio.sleep(0.1)
        return True

    async def dig_area(self, params: Dict[str, Any]) -> Dict[str, Any]:
        goal = params.get("goal") or ""
        coords = None
        if all(k in params for k in ("x1", "y1", "z1", "x2", "y2", "z2")):
            coords = (
                (params.get("x1"), params.get("y1"), params.get("z1")),
                (params.get("x2"), params.get("y2"), params.get("z2")),
            )
        elif isinstance(params.get("start"), (list, tuple)) and isinstance(
            params.get("end"), (list, tuple)
        ):
            start = params.get("start")
            end = params.get("end")
            if len(start) >= 3 and len(end) >= 3:
                coords = ((start[0], start[1], start[2]), (end[0], end[1], end[2]))
        elif isinstance(params.get("start"), dict) and isinstance(params.get("end"), dict):
            start = params.get("start")
            end = params.get("end")
            coords = (
                (start.get("x"), start.get("y"), start.get("z")),
                (end.get("x"), end.get("y"), end.get("z")),
            )
        if coords is None:
            coords = self._extract_two_coords_from_goal(str(goal))
        if coords is None:
            return {"ok": False, "error": "missing_coords"}

        def _as_int(value: Any) -> int:
            try:
                return int(round(float(value)))
            except (TypeError, ValueError):
                return 0

        (x1, y1, z1), (x2, y2, z2) = coords
        x1 = _as_int(x1)
        y1 = _as_int(y1)
        z1 = _as_int(z1)
        x2 = _as_int(x2)
        y2 = _as_int(y2)
        z2 = _as_int(z2)
        min_x, max_x = sorted((x1, x2))
        min_y, max_y = sorted((y1, y2))
        min_z, max_z = sorted((z1, z2))

        cfg = self._headful_config()
        max_blocks = int(params.get("max_blocks", cfg.get("dig_area_max_blocks", 512)))
        total = (max_x - min_x + 1) * (max_y - min_y + 1) * (max_z - min_z + 1)
        if total <= 0:
            return {"ok": False, "error": "invalid_bounds"}
        if max_blocks > 0 and total > max_blocks:
            return {
                "ok": False,
                "error": "area_too_large",
                "total": total,
                "max_blocks": max_blocks,
            }

        fill_walls = params.get("fill_walls")
        if fill_walls is None:
            fill_walls = self._extract_fill_walls_flag(str(goal))
        fill_walls = bool(fill_walls) if fill_walls is not None else False
        keep_walls = bool(params.get("keep_walls", fill_walls))

        attack_ms = int(params.get("attack_ms", cfg.get("dig_attack_ms", 1200)))
        distance = float(params.get("distance", cfg.get("dig_distance", 3.2)))
        move_timeout = float(params.get("move_timeout", cfg.get("dig_move_timeout", 4.0)))
        look_duration_ms = int(
            params.get("look_duration_ms", cfg.get("dig_look_duration_ms", 160))
        )
        step_delay_ms = int(
            params.get("step_delay_ms", cfg.get("dig_step_delay_ms", 80))
        )
        progress_every = int(
            params.get("progress_every", cfg.get("dig_progress_every", 20))
        )
        y_order = str(params.get("y_order", "top_down")).lower()
        if y_order in {"bottom", "bottom_up", "up"}:
            y_layers = list(range(min_y, max_y + 1))
        else:
            y_layers = list(range(max_y, min_y - 1, -1))

        tool = params.get("tool") or params.get("tool_type")
        if tool:
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot is not None:
                tool_name = None
                tool_type = str(tool).lower()
                if tool_type in {"pickaxe", "shovel", "axe", "hoe"}:
                    tool_name = self._best_tool_name(snapshot, tool_type)
                else:
                    tool_name = _normalize_item_name(tool)
                if tool_name:
                    await self._ensure_hotbar_slot_for_item(snapshot, [tool_name])
                    self._log_append(f"[dig-area] equip {tool_name}")

        if fill_walls and keep_walls:
            self._log_append("[dig-area] fill_walls enabled; keeping boundary blocks only.")

        self._log_append(
            f"[dig-area] start ({min_x},{min_y},{min_z}) -> ({max_x},{max_y},{max_z}) "
            f"total={total} keep_walls={keep_walls}"
        )

        dug = 0
        skipped = 0
        failed = 0
        for layer_idx, y in enumerate(y_layers):
            z_forward = list(range(min_z, max_z + 1))
            z_backward = list(range(max_z, min_z - 1, -1))
            z_iter = z_forward if layer_idx % 2 == 0 else z_backward
            for row_idx, z in enumerate(z_iter):
                if self._cancel_requested:
                    break
                x_forward = range(min_x, max_x + 1)
                x_backward = range(max_x, min_x - 1, -1)
                x_iter = x_forward if row_idx % 2 == 0 else x_backward
                for x in x_iter:
                    if self._cancel_requested:
                        break
                    if keep_walls and (
                        x == min_x or x == max_x or z == min_z or z == max_z
                    ):
                        skipped += 1
                        continue
                    ok = await self._dig_block_at(
                        {"x": x, "y": y, "z": z},
                        attack_ms=attack_ms,
                        distance=distance,
                        timeout=move_timeout,
                        look_duration_ms=look_duration_ms,
                    )
                    if ok:
                        dug += 1
                    else:
                        failed += 1
                    if step_delay_ms > 0:
                        await asyncio.sleep(step_delay_ms / 1000.0)
                    if progress_every > 0 and (dug + failed) % progress_every == 0:
                        self._log_append(
                            f"[dig-area] progress {dug} done, {failed} failed, {skipped} skipped"
                        )
            if self._cancel_requested:
                break

        if self._cancel_requested:
            self._cancel_requested = False
            return {
                "ok": False,
                "error": "cancelled",
                "dug": dug,
                "failed": failed,
                "skipped": skipped,
                "total": total,
            }
        return {
            "ok": True,
            "dug": dug,
            "failed": failed,
            "skipped": skipped,
            "total": total,
            "bounds": {
                "min": [min_x, min_y, min_z],
                "max": [max_x, max_y, max_z],
            },
            "keep_walls": keep_walls,
        }

    async def _harvest_nearby_crops(self, params: Dict[str, Any]) -> Dict[str, Any]:
        blocks = params.get("blocks")
        if blocks is None:
            blocks = list(CROP_BLOCKS)
        if not isinstance(blocks, list) or not blocks:
            return {"ok": False, "error": "missing_blocks"}
        radius = int(params.get("radius", 6))
        timeout = float(params.get("timeout", 4.0))
        attack_ms = int(params.get("attack_ms", 700))
        distance = float(params.get("distance", 2.5))
        look_at = bool(params.get("look_at", True))
        max_results = int(params.get("max_results", 2))
        cfg = self._headful_config()
        mature_only = bool(
            params.get(
                "mature_only",
                cfg.get("autonomy_harvest_mature_only", True),
            )
        )
        block_targets = [str(block) for block in blocks if block]
        if mature_only:
            find_result = await self._find_mature_crops(
                block_targets,
                radius=radius,
                max_results=max_results,
                timeout=timeout,
            )
        else:
            find_result = await self._find_blocks(
                block_targets,
                radius=radius,
                max_results=max_results,
                timeout=timeout,
            )
        if not find_result.get("ok"):
            return {"ok": False, "error": "crop_not_found"}
        positions = [
            pos for pos in (find_result.get("positions") or []) if isinstance(pos, dict)
        ]
        if not positions:
            return {"ok": False, "error": "crop_not_found"}
        broken = 0
        for pos in positions:
            if broken >= max_results:
                break
            await self._move_near_position(pos, distance=distance, timeout=timeout)
            if look_at:
                await self._look_at_position(pos, duration_ms=200)
            await self._adapter.send_action(
                {"type": "setKey", "key": "attack", "pressed": True},
                self._headful_config(),
            )
            await asyncio.sleep(max(0.2, attack_ms / 1000.0))
            await self._adapter.send_action(
                {"type": "setKey", "key": "attack", "pressed": False},
                self._headful_config(),
            )
            broken += 1
            await asyncio.sleep(0.25)
        return {"ok": broken > 0, "broken": broken, "blocks": blocks}

    async def view_container(self, params: Dict[str, Any]) -> Dict[str, Any]:
        open_result = await self.open_container(params)
        if not open_result.get("ok"):
            return open_result
        return {
            "ok": True,
            "position": open_result.get("position"),
            "snapshot": open_result.get("snapshot"),
        }

    async def take_from_container(self, params: Dict[str, Any]) -> Dict[str, Any]:
        item = params.get("item")
        count = int(params.get("count", 1))
        payload = dict(params)
        if item:
            payload["item"] = item
            payload["count"] = count
        payload["open_table"] = False
        payload["skip_craft"] = True
        return await self.craft_from_container(payload)

    async def craft_from_container(self, params: Dict[str, Any]) -> Dict[str, Any]:
        item_name = _normalize_item_name(params.get("item"))
        count = int(params.get("count", 1))
        if not item_name:
            return {"ok": False, "error": "missing_item"}
        cfg = self._headful_config()
        use_llm_orchestrator = bool(
            params.get("use_llm_orchestrator", cfg.get("use_llm_orchestrator", False))
        )
        if use_llm_orchestrator and not bool(params.get("_no_llm_orchestrator", False)):
            return await self._llm_orchestrate_craft(params)
        results: List[Dict[str, Any]] = []
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        container_items = params.get("container_items")
        container_item = params.get("container_item")
        smart_pickup = bool(params.get("smart_pickup", True))
        precise_pickup = bool(
            params.get("precise_pickup", params.get("exact_pickup", True))
        )
        allow_smelting = bool(params.get("allow_smelting", True))
        max_slots = int(params.get("max_slots", 54))
        multi_container_default = smart_pickup or container_item or isinstance(container_items, list)
        multi_container = bool(params.get("multi_container", multi_container_default))
        if not smart_pickup and not container_item and not isinstance(container_items, list):
            multi_container = False
        use_container_counts = bool(params.get("use_container_counts", False))
        verify_transfer = bool(params.get("verify_transfer", True))
        specific_items = bool(container_item or isinstance(container_items, list))
        close_container = bool(params.get("close_container", True))
        deny_raw = params.get("container_denylist", cfg.get("container_denylist"))
        if deny_raw is None:
            deny_raw = ["ender_chest"]
        if isinstance(deny_raw, str):
            deny_list = [deny_raw]
        elif isinstance(deny_raw, list):
            deny_list = [str(item) for item in deny_raw if item]
        else:
            deny_list = []
        deny_set = {self._normalize_block_name(item).split(":", 1)[1] for item in deny_list}
        default_radius = int(cfg.get("container_radius_default", 5))
        container_radius = int(
            params.get(
                "container_radius",
                params.get("search_radius", params.get("radius", default_radius)),
            )
        )
        container_timeout = float(params.get("container_timeout", params.get("timeout", 4.0)))
        move = bool(params.get("move", True))
        face = params.get("face", "up")
        self._debug_log(
            (
                "craft_from_container start "
                f"item={item_name} count={count} smart_pickup={smart_pickup} "
                f"precise={precise_pickup} multi_container={multi_container}"
            ),
            params,
        )

        needed: Optional[Dict[str, int]] = None
        remaining: Dict[str, int] = {}
        if container_item or isinstance(container_items, list):
            items: List[str] = []
            if isinstance(container_items, list):
                items.extend([_normalize_item_name(x) for x in container_items if x])
            if container_item:
                items.append(_normalize_item_name(container_item))
            needed = {name: 9999 for name in items if name}
            remaining = dict(needed)

        transfer_result: Dict[str, Any] | None = None
        async def _post_transfer_update() -> None:
            nonlocal remaining, snapshot, transfer_result, smelt_groups
            if not transfer_result:
                return
            actions_count = int(transfer_result.get("actions", 0))
            if actions_count > 0:
                timeout = min(10.0, max(1.0, actions_count * 0.3 + 0.6))
                await self._wait_for_queue_empty(actions_count, timeout=timeout)
            if not verify_transfer or not smart_pickup or needed is None or specific_items:
                return
            raw_verify = await self._get_snapshot(refresh=True)
            snapshot_verify = ScreenSnapshot.from_dict(raw_verify)
            if snapshot_verify is None:
                return
            inventory_counts = self._build_counts(
                snapshot_verify.slots, ("player_main", "player_hotbar")
            )
            available_for_choice = dict(inventory_counts)
            remaining = self._compute_transfer_requirements_from_inventory(
                item_name,
                count,
                dict(inventory_counts),
                available_for_choice,
                allow_smelting=allow_smelting,
            )
            smelt_groups = self._build_smelt_input_groups(remaining, item_name)
            transfer_result["verified_remaining"] = remaining
            snapshot = snapshot_verify
            self._debug_log(
                f"craft_from_container verify remaining={remaining}",
                params,
            )
        container_open = bool(
            snapshot and snapshot.screen_open and self._snapshot_has_container(snapshot)
        )
        settle_ms = int(params.get("container_settle_ms", cfg.get("container_settle_ms", 400)))
        recheck_ms = int(params.get("container_recheck_ms", cfg.get("container_recheck_ms", 250)))
        close_timeout_ms = int(params.get("close_timeout_ms", cfg.get("screen_close_timeout_ms", 800)))
        smelt_groups = None

        async def _transfer_with_retry(
            current_snapshot: ScreenSnapshot, current_remaining: Dict[str, int]
        ) -> Tuple[Dict[str, Any], Dict[str, int]]:
            transfer = await self._transfer_needed_from_container(
                current_snapshot,
                current_remaining,
                max_slots=max_slots,
                precise=precise_pickup,
                allow_smelting=allow_smelting,
                smelt_groups=smelt_groups,
            )
            next_remaining = transfer.get("remaining", current_remaining)
            if needed is not None:
                transfer["needed"] = needed
            if (
                recheck_ms > 0
                and next_remaining
                and transfer.get("actions", 0) == 0
                and next_remaining == current_remaining
            ):
                await asyncio.sleep(recheck_ms / 1000.0)
                raw_retry = await self._get_snapshot(refresh=True)
                snapshot_retry = ScreenSnapshot.from_dict(raw_retry)
                if (
                    snapshot_retry
                    and snapshot_retry.screen_open
                    and self._snapshot_has_container(snapshot_retry)
                ):
                    snapshot_retry = await self._stabilize_container_snapshot(
                        snapshot_retry, settle_ms
                    )
                    retry_result = await self._transfer_needed_from_container(
                        snapshot_retry,
                        next_remaining,
                        max_slots=max_slots,
                        precise=precise_pickup,
                        allow_smelting=allow_smelting,
                        smelt_groups=smelt_groups,
                    )
                    if needed is not None:
                        retry_result["needed"] = needed
                    transfer["retry"] = retry_result
                    next_remaining = retry_result.get("remaining", next_remaining)
            return transfer, next_remaining
        if container_open and snapshot is not None:
            snapshot = await self._stabilize_container_snapshot(snapshot, settle_ms)
            if smart_pickup and needed is None:
                inventory_counts = self._build_counts(
                    snapshot.slots, ("player_main", "player_hotbar")
                )
                container_counts = self._build_counts(
                    snapshot.slots,
                    ("container", "container_input", "container_output", "container_fuel"),
                )
                available_for_choice = dict(inventory_counts)
                for key, val in container_counts.items():
                    available_for_choice[key] = available_for_choice.get(key, 0) + val
                if use_container_counts:
                    needed = self._compute_transfer_requirements(
                        item_name,
                        count,
                        inventory_counts,
                        available_for_choice,
                        allow_smelting=allow_smelting,
                    )
                else:
                    needed = self._compute_transfer_requirements_from_inventory(
                        item_name,
                        count,
                        inventory_counts,
                        available_for_choice,
                        allow_smelting=allow_smelting,
                    )
                remaining = dict(needed)
                smelt_groups = self._build_smelt_input_groups(needed, item_name)
                self._debug_log(f"craft_from_container needed={needed}", params)
            if smart_pickup or needed is not None:
                transfer_result, remaining = await _transfer_with_retry(
                    snapshot, remaining
                )
                self._debug_log(
                    f"craft_from_container transfer remaining={remaining}",
                    params,
                )
            else:
                transfer_result = await self.container_transfer(
                    {
                        "direction": "to_inventory",
                        "item": None,
                        "max_slots": max_slots,
                    }
                )
            results.append({"step": "transfer_container", "result": transfer_result})
            if not transfer_result.get("ok"):
                return {"ok": False, "error": "transfer_failed", "steps": results}
            await _post_transfer_update()
            if close_container or (remaining and multi_container):
                await self._adapter.send_action(
                    {"type": "closeScreen"}, self._headful_config()
                )
                await self._wait_for_screen_closed(timeout=close_timeout_ms / 1000.0)
                await asyncio.sleep(0.2)

        expand_raw = params.get("container_search_radii", cfg.get("container_search_radii"))
        if isinstance(expand_raw, list):
            expand_radii = []
            for value in expand_raw:
                try:
                    expand_radii.append(int(value))
                except (TypeError, ValueError):
                    continue
        else:
            expand_radii = [15, 50]
        search_radii = [container_radius]
        for radius in expand_radii:
            try:
                value = int(radius)
            except (TypeError, ValueError):
                continue
            if value > search_radii[-1]:
                search_radii.append(value)

        if (not container_open) or (remaining and multi_container):
            positions: List[Dict[str, Any]] = []
            if multi_container:
                targets: List[str] = []
                blocks = params.get("container_blocks")
                block = params.get("container_block")
                if isinstance(blocks, list):
                    targets.extend([str(b) for b in blocks if b])
                if block:
                    targets.append(str(block))
                if not targets:
                    targets = list(CONTAINER_BLOCKS)
                    if allow_smelting and bool(cfg.get("include_smelting_blocks", True)):
                        targets.extend(SMELTING_BLOCKS)
                if deny_set:
                    targets = [
                        t
                        for t in targets
                        if self._normalize_block_name(t).split(":", 1)[1] not in deny_set
                    ]
                max_containers = int(params.get("max_containers", params.get("max_results", 6)))
                registry = await self._load_container_registry()
                for radius in search_radii:
                    find_result = await self._find_blocks(
                        targets,
                        radius=radius,
                        max_results=max_containers,
                        timeout=container_timeout,
                    )
                    results.append(
                        {"step": "find_containers", "radius": radius, "result": find_result}
                    )
                    if find_result.get("ok"):
                        positions = [
                            pos
                            for pos in (find_result.get("positions") or [])
                            if isinstance(pos, dict)
                        ]
                        if positions:
                            await self._register_found_positions(positions)
                            break
                    positions = []
                if not positions and registry:
                    positions = self._registry_positions_within_radius(
                        registry, search_radii[-1]
                    )
                if deny_set and positions:
                    filtered_positions = []
                    for pos in positions:
                        block_name = str(pos.get("block", ""))
                        if block_name:
                            if block_name.split(":", 1)[-1] in deny_set:
                                continue
                        filtered_positions.append(pos)
                    positions = filtered_positions
                if positions:
                    positions = self._sort_container_positions(
                        positions, registry, remaining, smelt_groups
                    )
                if remaining and not positions:
                    return {
                        "ok": False,
                        "error": "container_not_found",
                        "missing": remaining,
                        "steps": results,
                    }

            if not positions and not container_open:
                open_params = {
                    "block": params.get("container_block"),
                    "blocks": params.get("container_blocks"),
                    "radius": container_radius,
                    "move": move,
                    "face": face,
                    "timeout": container_timeout,
                    "ensure_closed": True,
                    "close_timeout_ms": close_timeout_ms,
                    "place_if_missing": bool(params.get("place_container_if_missing", False)),
                }
                open_result = await self.open_container(open_params)
                results.append({"step": "open_container", "result": open_result})
                if not open_result.get("ok"):
                    # 如果完全找不到容器且不强制需要容器，则跳过继续后续步骤
                    if not remaining:
                        pass
                    else:
                        return {"ok": False, "error": "open_container_failed", "steps": results}
                snapshot = open_result.get("snapshot")
                if snapshot is None:
                    raw = await self._get_snapshot(refresh=True)
                    snapshot = ScreenSnapshot.from_dict(raw)
                if snapshot is None:
                    return {"ok": False, "error": "no_snapshot", "steps": results}
                snapshot = await self._stabilize_container_snapshot(snapshot, settle_ms)
                if smart_pickup and needed is None:
                    inventory_counts = self._build_counts(
                        snapshot.slots, ("player_main", "player_hotbar")
                    )
                    container_counts = self._build_counts(
                        snapshot.slots,
                        ("container", "container_input", "container_output", "container_fuel"),
                    )
                    available_for_choice = dict(inventory_counts)
                    for key, val in container_counts.items():
                        available_for_choice[key] = available_for_choice.get(key, 0) + val
                    if use_container_counts:
                        needed = self._compute_transfer_requirements(
                            item_name,
                            count,
                            inventory_counts,
                            available_for_choice,
                            allow_smelting=allow_smelting,
                        )
                    else:
                        needed = self._compute_transfer_requirements_from_inventory(
                            item_name,
                            count,
                            inventory_counts,
                            available_for_choice,
                            allow_smelting=allow_smelting,
                        )
                    remaining = dict(needed)
                    smelt_groups = self._build_smelt_input_groups(needed, item_name)
                    self._debug_log(f"craft_from_container needed={needed}", params)
                if smart_pickup or needed is not None:
                    transfer_result, remaining = await _transfer_with_retry(
                        snapshot, remaining
                    )
                    self._debug_log(
                        f"craft_from_container transfer remaining={remaining}",
                        params,
                    )
                else:
                    transfer_result = await self.container_transfer(
                        {
                            "direction": "to_inventory",
                            "item": None,
                            "max_slots": max_slots,
                        }
                    )
                results.append({"step": "transfer_container", "result": transfer_result})
                if not transfer_result.get("ok"):
                    return {"ok": False, "error": "transfer_failed", "steps": results}
                await _post_transfer_update()
                if close_container:
                    await self._adapter.send_action(
                        {"type": "closeScreen"}, self._headful_config()
                    )
                    await self._wait_for_screen_closed(timeout=close_timeout_ms / 1000.0)
                    await asyncio.sleep(0.2)
            elif positions:
                visited = set()
                for pos in positions:
                    if needed is not None and not remaining:
                        break
                    try:
                        key = (int(pos.get("x")), int(pos.get("y")), int(pos.get("z")))
                    except (TypeError, ValueError):
                        key = None
                    if key and key in visited:
                        continue
                    if key:
                        visited.add(key)
                    open_result = await self.open_container(
                        {
                            "position": pos,
                            "move": move,
                            "face": face,
                            "timeout": container_timeout,
                            "ensure_closed": True,
                            "close_timeout_ms": close_timeout_ms,
                        }
                    )
                    results.append(
                        {"step": "open_container", "position": pos, "result": open_result}
                    )
                    if not open_result.get("ok"):
                        continue
                    snapshot = open_result.get("snapshot")
                    if snapshot is None:
                        raw = await self._get_snapshot(refresh=True)
                        snapshot = ScreenSnapshot.from_dict(raw)
                    if snapshot is None:
                        return {"ok": False, "error": "no_snapshot", "steps": results}
                    snapshot = await self._stabilize_container_snapshot(snapshot, settle_ms)
                    if smart_pickup and needed is None:
                        inventory_counts = self._build_counts(
                            snapshot.slots, ("player_main", "player_hotbar")
                        )
                        container_counts = self._build_counts(
                            snapshot.slots,
                            ("container", "container_input", "container_output", "container_fuel"),
                        )
                        available_for_choice = dict(inventory_counts)
                        for key, val in container_counts.items():
                            available_for_choice[key] = available_for_choice.get(key, 0) + val
                        if use_container_counts:
                            needed = self._compute_transfer_requirements(
                                item_name,
                                count,
                                inventory_counts,
                                available_for_choice,
                                allow_smelting=allow_smelting,
                            )
                        else:
                            needed = self._compute_transfer_requirements_from_inventory(
                                item_name,
                                count,
                                inventory_counts,
                                available_for_choice,
                                allow_smelting=allow_smelting,
                            )
                        remaining = dict(needed)
                        smelt_groups = self._build_smelt_input_groups(needed, item_name)
                        self._debug_log(f"craft_from_container needed={needed}", params)
                    if smart_pickup or needed is not None:
                        transfer_result, remaining = await _transfer_with_retry(
                            snapshot, remaining
                        )
                        self._debug_log(
                            f"craft_from_container transfer remaining={remaining}",
                            params,
                        )
                    else:
                        transfer_result = await self.container_transfer(
                            {
                                "direction": "to_inventory",
                                "item": None,
                                "max_slots": max_slots,
                            }
                        )
                    results.append(
                        {
                            "step": "transfer_container",
                            "position": pos,
                            "result": transfer_result,
                        }
                    )
                    if not transfer_result.get("ok"):
                        return {
                            "ok": False,
                            "error": "transfer_failed",
                            "steps": results,
                        }
                    await _post_transfer_update()
                    await self._adapter.send_action(
                        {"type": "closeScreen"}, self._headful_config()
                    )
                    await self._wait_for_screen_closed(timeout=close_timeout_ms / 1000.0)
                    await asyncio.sleep(0.2)

        if bool(params.get("skip_craft", False)):
            return {"ok": True, "remaining": remaining, "steps": results}

        opened_table = False
        if bool(params.get("open_table", True)):
            table_radius = int(
                params.get("table_radius", params.get("search_radius", params.get("radius", 8)))
            )
            open_table = await self.open_crafting_table(
                {
                    "radius": table_radius,
                    "move": params.get("move", True),
                }
            )
            results.append({"step": "open_crafting_table", "result": open_table})
            if not open_table.get("ok"):
                return {
                    "ok": False,
                    "error": "open_crafting_table_failed",
                    "steps": results,
                }
            opened_table = True

        craft_params = dict(params)
        craft_params["item"] = item_name
        craft_params["count"] = count
        craft_params["auto_open_table"] = bool(params.get("auto_open_table", True))
        if opened_table:
            craft_params["open_table_attempted"] = True
        craft_result = await self.craft_item(craft_params, execute=True)
        results.append({"step": "craft", "result": craft_result})
        return {"ok": bool(craft_result.get("ok")), "result": craft_result, "steps": results}

    async def craftable_catalog(self, params: Dict[str, Any]) -> Dict[str, Any]:
        catalog = self._build_craftable_catalog()
        include_all = bool(params.get("include_all", False))
        include_basic = bool(params.get("include_basic", True))
        category = params.get("category")
        summary = {
            "ok": True,
            "total": len(catalog["all"]),
            "basic_count": len(catalog["basic"]),
            "categories": {
                name: len(items) for name, items in catalog["categories"].items()
            },
        }
        if include_basic:
            summary["basic"] = catalog["basic"]
        if include_all:
            summary["all"] = catalog["all"]
        if category:
            key = str(category)
            items = catalog["categories"].get(key)
            if items is None:
                return {
                    "ok": False,
                    "error": "unknown_category",
                    "available": sorted(catalog["categories"].keys()),
                }
            summary["category"] = key
            summary["items"] = items
        return summary

    async def _resolve_bed_position(self, radius: int = 8) -> Optional[Dict[str, Any]]:
        bed_targets = [
            "white_bed",
            "red_bed",
            "blue_bed",
            "black_bed",
            "cyan_bed",
            "gray_bed",
            "green_bed",
            "light_blue_bed",
            "light_gray_bed",
            "lime_bed",
            "magenta_bed",
            "orange_bed",
            "pink_bed",
            "purple_bed",
            "yellow_bed",
            "brown_bed",
        ]
        result = await self._find_blocks(
            bed_targets,
            radius=radius,
            max_results=3,
            timeout=2.0,
        )
        if result.get("ok") and isinstance(result.get("positions"), list) and result["positions"]:
            return result["positions"][0]
        registry = await self._load_container_registry()
        if registry and isinstance(registry.get("containers"), dict):
            for _, meta in registry["containers"].items():
                block = str(meta.get("block", ""))
                if block.endswith("_bed"):
                    pos = meta.get("pos")
                    if pos:
                        return pos
        return None

    async def _ensure_bed(self) -> Dict[str, Any]:
        pos = await self._resolve_bed_position(radius=8)
        if pos:
            return {"ok": True, "position": pos, "found": True}
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        if snapshot:
            bed_items = [slot for slot in snapshot.slots if slot.item and slot.item.name.endswith("_bed")]
            if bed_items:
                _, snap = await self._ensure_hotbar_slot_for_item(
                    snapshot, [bed_items[0].item.name]
                )
                placed = await self._place_block_from_hotbar(snap, face="up", look_duration_ms=200)
                if placed:
                    pos = await self._resolve_bed_position(radius=8)
                    if pos:
                        return {"ok": True, "position": pos, "placed": True}
        return {"ok": False, "error": "bed_not_found"}

    async def _sleep_in_bed(self) -> Dict[str, Any]:
        pos = await self._resolve_bed_position(radius=10)
        if not pos:
            ensured = await self._ensure_bed()
            if not ensured.get("ok"):
                return ensured
            pos = ensured.get("position")
        if not pos:
            return {"ok": False, "error": "bed_not_found"}
        await self._move_near_position(pos, distance=1.6, timeout=4.0)
        await self._look_at_position(pos, duration_ms=200)
        used = await self._use_block_at(pos, face="up")
        if used:
            return {"ok": True, "position": pos}
        return {"ok": False, "error": "sleep_failed", "position": pos}

    def _crafting_allowlist(self) -> Optional[set[str]]:
        cfg = self._headful_config()
        allow = cfg.get("crafting_allowlist")
        deny = cfg.get("crafting_denylist")
        tier = str(cfg.get("crafting_tier", "all")).lower()
        allowed: Optional[set[str]] = None
        if isinstance(allow, list) and allow:
            allowed = {_normalize_item_name(item) for item in allow if item}
        elif tier == "basic":
            allowed = set(self._build_craftable_catalog()["basic"])
        if allowed is None:
            return None
        if isinstance(deny, list) and deny:
            denied = {_normalize_item_name(item) for item in deny if item}
            allowed -= denied
        return allowed

    def _is_craft_allowed(self, item_name: str, params: Dict[str, Any]) -> bool:
        if params.get("internal"):
            return True
        allowlist = self._crafting_allowlist()
        if allowlist is None:
            return True
        return item_name in allowlist

    def _build_counts(self, slots: Iterable[SlotInfo], groups: Tuple[str, ...]) -> Dict[str, int]:
        counts: Dict[str, int] = {}
        for slot in slots:
            if slot.group not in groups or slot.item is None:
                continue
            counts[slot.item.name] = counts.get(slot.item.name, 0) + slot.item.count
        return counts

    def _inventory_counts(self, snapshot: ScreenSnapshot) -> Dict[str, int]:
        return self._build_counts(snapshot.slots, ("player_main", "player_hotbar"))

    def _inventory_has_item(
        self, snapshot: ScreenSnapshot, item_name: str, count: int = 1
    ) -> bool:
        if count <= 0:
            return True
        inventory = self._inventory_counts(snapshot)
        return inventory.get(_normalize_item_name(item_name), 0) >= count

    def _state_summary_for_llm(self, plan_graph: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        state = getattr(self._adapter, "last_state", {}) or {}
        summary: Dict[str, Any] = {}
        try:
            dim = state.get("dimension")
            world_time = int(state.get("worldTime", 0))
            day_time = world_time % 24000
            summary["dimension"] = dim
            summary["world_time"] = world_time
            summary["day_time"] = day_time
            summary["is_night"] = bool(day_time >= 13000 and day_time <= 23000)
            summary["env"] = state.get("envSample")
        except Exception:
            pass
        try:
            cfg = self._headful_config()
            summary["smart_guard_enabled"] = bool(cfg.get("enable_smart_guard", True))
            summary["smart_gather_enabled"] = bool(cfg.get("enable_smart_gather", True))
        except Exception:
            pass
        try:
            entities = state.get("nearbyEntities", {})
            if isinstance(entities, dict):
                items = entities.get("items") or []
                players = []
                hostiles = []
                for e in items:
                    etype = (e.get("type") or "").split(":")[-1]
                    name = e.get("name") or ""
                    dist = e.get("dist")
                    if etype == "player":
                        players.append({"name": name, "dist": dist})
                    elif etype:
                        hostiles.append({"type": etype, "dist": dist})
                summary["nearby_players"] = players[:5]
                summary["nearby_hostiles"] = hostiles[:5]
        except Exception:
            pass
        try:
            registry = None
            if self._container_registry_cache is not None:
                registry = self._container_registry_cache
            summary["known_stations"] = []
            summary["known_containers"] = []
            if registry and isinstance(registry, dict):
                containers = registry.get("containers") or {}
                for pos_key, meta in containers.items():
                    block = meta.get("block") or ""
                    if not block:
                        continue
                    if any(
                        block.endswith(suf)
                        for suf in (
                            "crafting_table",
                            "furnace",
                            "blast_furnace",
                            "smoker",
                            "brewing_stand",
                            "enchanting_table",
                            "anvil",
                            "smithing_table",
                            "grindstone",
                            "loom",
                            "stonecutter",
                            "cartography_table",
                            "fletching_table",
                            "bed",
                            "chest",
                            "barrel",
                        )
                    ):
                        summary["known_stations"].append(
                            {"block": block, "pos": meta.get("pos")}
                        )
                    summary["known_containers"].append(
                        {
                            "block": block,
                            "pos": meta.get("pos"),
                            "last_seen": meta.get("last_seen"),
                        }
                    )
        except Exception:
            pass
        if plan_graph:
            summary["plan_graph"] = plan_graph
        return summary

    def _slots_by_group(self, slots: Iterable[SlotInfo], groups: Tuple[str, ...]) -> List[SlotInfo]:
        return [slot for slot in slots if slot.group in groups]

    def _build_player_slot_state(self, snapshot: ScreenSnapshot) -> List[Dict[str, Any]]:
        slots = self._slots_by_group(snapshot.slots, ("player_main", "player_hotbar"))
        state: List[Dict[str, Any]] = []
        for slot in slots:
            if slot.item is None:
                state.append(
                    {
                        "slot": slot.slot,
                        "item": None,
                        "count": 0,
                        "max_count": 0,
                    }
                )
            else:
                state.append(
                    {
                        "slot": slot.slot,
                        "item": slot.item.name,
                        "count": slot.item.count,
                        "max_count": slot.item.max_count,
                    }
                )
        return state

    def _find_player_slot_for_item(
        self,
        player_slots: List[Dict[str, Any]],
        item_name: str,
        default_max: int,
    ) -> Optional[Dict[str, Any]]:
        for slot in player_slots:
            if slot["item"] == item_name and slot["count"] < slot["max_count"]:
                return slot
        for slot in player_slots:
            if slot["item"] is None:
                if slot["max_count"] <= 0:
                    slot["max_count"] = default_max
                return slot
        return None

    def _player_capacity_for_item(
        self,
        player_slots: List[Dict[str, Any]],
        item_name: str,
        default_max: int,
    ) -> int:
        capacity = 0
        for slot in player_slots:
            if slot["item"] == item_name:
                capacity += max(0, slot["max_count"] - slot["count"])
            elif slot["item"] is None:
                capacity += default_max
        return capacity

    async def _wait_for_queue_empty(self, actions: int, timeout: float = 6.0) -> None:
        if actions <= 0:
            return
        await asyncio.sleep(0.25)
        deadline = time.time() + max(1.0, timeout)
        while time.time() < deadline:
            state = getattr(self._adapter, "last_state", None)
            queue_len: Optional[int] = None
            if isinstance(state, dict) and "queue_length" in state:
                try:
                    queue_len = int(state.get("queue_length"))
                except (TypeError, ValueError):
                    queue_len = None
            if queue_len is not None and queue_len <= 0:
                return
            await asyncio.sleep(0.1)

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
        try:
            extra_dir = self._registry_base_dir() / "docs"
            if extra_dir.exists():
                extra_files = list(extra_dir.glob("*.md")) + list(extra_dir.glob("*.txt"))
                for path in sorted(extra_files)[:12]:
                    docs.append((path.name, path))
        except Exception:
            pass
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
        try:
            self._person_service.upsert_role(user_id, "system_doc")
        except Exception:
            pass
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
                    scope="knowledge",
                    source="mindcraft_doc",
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

    def _snapshot_to_raw(self, snapshot: ScreenSnapshot) -> Dict[str, Any]:
        slots = []
        for slot in snapshot.slots:
            stack = None
            if slot.item:
                stack = {
                    "itemId": slot.item.item_id,
                    "count": slot.item.count,
                    "maxCount": slot.item.max_count,
                }
            slots.append(
                {
                    "slot": slot.slot,
                    "group": slot.group,
                    "invIndex": slot.inv_index,
                    "x": slot.x,
                    "y": slot.y,
                    "stack": stack,
                    "equip": slot.equip,
                }
            )
        cursor = None
        if snapshot.cursor:
            cursor = {
                "itemId": snapshot.cursor.item_id,
                "count": snapshot.cursor.count,
                "maxCount": snapshot.cursor.max_count,
            }
        return {
            "handler": snapshot.handler,
            "screenOpen": snapshot.screen_open,
            "title": snapshot.title,
            "cursor": cursor,
            "slots": slots,
        }

    def serialize_result(self, data: Any) -> Any:
        if isinstance(data, ScreenSnapshot):
            return self._snapshot_to_raw(data)
        if isinstance(data, dict):
            return {key: self.serialize_result(value) for key, value in data.items()}
        if isinstance(data, list):
            return [self.serialize_result(value) for value in data]
        return data

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
            if self._cancel_requested:
                break
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
            elif action_type == "move_to":
                await self.go_to_position(
                    {
                        "x": action.get("x"),
                        "y": action.get("y"),
                        "z": action.get("z"),
                        "distance": action.get("distance", 1.5),
                        "timeout": action.get("timeout", 8.0),
                    }
                )
                executed += 1
            elif action_type == "go_to_nearest_block":
                await self.go_to_nearest_block(
                    {
                        "block": action.get("block"),
                        "blocks": action.get("blocks"),
                        "radius": action.get("radius", 16),
                        "distance": action.get("distance", 3.5),
                        "timeout": action.get("timeout", 6.0),
                        "look_at": action.get("look_at", True),
                        "look_duration_ms": action.get("look_duration_ms", 200),
                    }
                )
                executed += 1
            elif action_type == "go_to_player":
                await self.go_to_player(
                    {
                        "player_name": action.get("player")
                        or action.get("player_name")
                        or action.get("name")
                        or action.get("target"),
                        "distance": action.get("distance", 3.0),
                        "timeout": action.get("timeout", 6.0),
                    }
                )
                executed += 1
            elif action_type == "follow_player":
                await self.follow_player(
                    {
                        "player_name": action.get("player")
                        or action.get("player_name")
                        or action.get("name")
                        or action.get("target"),
                        "duration_sec": action.get("duration_sec", 12.0),
                        "distance": action.get("distance", 3.0),
                    }
                )
                executed += 1
            elif action_type == "attack_nearest":
                await self.attack_nearest(
                    {
                        "entity_type": action.get("entity_type"),
                        "range": action.get("range", 18.0),
                        "duration_sec": action.get("duration_sec", 6.0),
                    }
                )
                executed += 1
            elif action_type == "defend_self":
                await self.defend_self(
                    {
                        "range": action.get("range", 12.0),
                        "duration_sec": action.get("duration_sec", 10.0),
                    }
                )
                executed += 1
            elif action_type == "smart_guard":
                await self.smart_guard(
                    {
                        "range": action.get("range", 12.0),
                        "duration_sec": action.get("duration_sec", 10.0),
                    }
                )
                executed += 1
            elif action_type == "smart_gather":
                await self.smart_gather(
                    {
                        "range": action.get("range", 10.0),
                    }
                )
                executed += 1
            elif action_type == "place_block":
                await self.place_block(
                    {
                        "block": action.get("block"),
                        "face": action.get("face", "up"),
                    }
                )
                executed += 1
            elif action_type == "pillar_up":
                await self.pillar_up(
                    {
                        "steps": action.get("steps", action.get("count", 1)),
                        "delay_ms": action.get("delay_ms", action.get("delayMs", 320)),
                    }
                )
                executed += 1
            elif action_type == "dig_area":
                await self.dig_area(
                    {
                        "x1": action.get("x1"),
                        "y1": action.get("y1"),
                        "z1": action.get("z1"),
                        "x2": action.get("x2"),
                        "y2": action.get("y2"),
                        "z2": action.get("z2"),
                        "fill_walls": action.get("fill_walls"),
                        "keep_walls": action.get("keep_walls"),
                        "max_blocks": action.get("max_blocks"),
                        "attack_ms": action.get("attack_ms"),
                        "distance": action.get("distance"),
                        "move_timeout": action.get("move_timeout"),
                        "look_duration_ms": action.get("look_duration_ms"),
                        "step_delay_ms": action.get("step_delay_ms"),
                        "progress_every": action.get("progress_every"),
                        "y_order": action.get("y_order"),
                    }
                )
                executed += 1
            elif action_type == "useTarget":
                await self._adapter.send_action({"type": "useTarget"}, self._headful_config())
                executed += 1
            if step_delay_ms > 0:
                await asyncio.sleep(step_delay_ms / 1000)
            if refresh_snapshot:
                await self._get_snapshot(refresh=True)
        return executed

    async def cancel_current(self) -> Dict[str, Any]:
        self._cancel_requested = True
        await self._adapter.send_action({"type": "releaseAllKeys"}, self._headful_config())
        await self._adapter.send_action({"type": "stopInput"}, self._headful_config())
        await self._adapter.send_action({"type": "stopMove"}, self._headful_config())
        await self._adapter.send_action({"type": "stopLook"}, self._headful_config())
        await self._adapter.send_action({"type": "closeScreen"}, self._headful_config())
        return {"ok": True}

    def _resolve_llm_config(self, params: Dict[str, Any]) -> Dict[str, Any]:
        cfg = self._config()
        require_frontend_raw = params.get(
            "llm_require_frontend", cfg.get("llm_require_frontend", False)
        )
        if isinstance(require_frontend_raw, str):
            require_frontend = require_frontend_raw.lower() in {"1", "true", "yes", "on"}
        else:
            require_frontend = bool(require_frontend_raw)

        param_api_key = params.get("llm_api_key") or params.get("agent_api_key")
        param_base_url = params.get("llm_base_url") or params.get("agent_base_url")
        param_model = params.get("llm_model") or params.get("agent_model")

        if require_frontend:
            if not param_api_key and not param_base_url:
                return {"ok": False, "error": "llm_config_missing"}
            return {
                "ok": True,
                "api_key": param_api_key,
                "base_url": param_base_url,
                "model": param_model or cfg.get("agent_model"),
            }

        return {
            "ok": True,
            "api_key": param_api_key or cfg.get("agent_api_key"),
            "base_url": param_base_url or cfg.get("agent_base_url"),
            "model": param_model or cfg.get("agent_model"),
        }

    def _validate_orchestrator_actions(
        self, actions: List[Any]
    ) -> Tuple[List[Dict[str, Any]], List[str]]:
        allowed = {
            "ensure_crafting_table",
            "ensure_furnace",
            "ensure_bed",
            "ensure_chest",
            "gather_item",
            "smelt_output",
            "craft_item",
            "brew_item",
            "smith_item",
            "enchant_item",
            "trade_item",
            "sleep",
            "follow_player",
            "guard_player",
            "smart_guard",
            "smart_gather",
            "store_inventory",
            "set_respawn",
            "move_to",
            "go_to_player",
            "go_to_nearest_block",
            "pillar_up",
            "pickup_nearby",
            "open_container",
            "open_crafting_table",
            "open_furnace",
            "open_brewing_stand",
            "open_smithing_table",
            "open_enchanting_table",
            "open_trade",
            "collect_block",
            "alert_main_brain",
            "close_screen",
            "wait",
        }
        cleaned: List[Dict[str, Any]] = []
        warnings: List[str] = []
        for idx, action in enumerate(actions):
            if not isinstance(action, dict):
                warnings.append(f"step {idx}: action_not_object")
                continue
            action_type = str(action.get("type") or "")
            if action_type not in allowed:
                warnings.append(f"step {idx}: action_not_allowed:{action_type}")
                continue
            normalized = {"type": action_type}
            if action_type in {
                "gather_item",
                "smelt_output",
                "craft_item",
                "brew_item",
                "smith_item",
                "enchant_item",
                "trade_item",
            }:
                item = _normalize_item_name(action.get("item"))
                count = int(action.get("count", 1))
                if not item:
                    warnings.append(f"step {idx}: missing_item")
                    continue
                normalized["item"] = item
                normalized["count"] = max(1, count)
            elif action_type in {"follow_player", "guard_player"}:
                target = (
                    action.get("player")
                    or action.get("player_name")
                    or action.get("name")
                    or action.get("target")
                )
                if target:
                    normalized["player"] = str(target)
                normalized["duration_sec"] = float(action.get("duration_sec", 20.0))
            elif action_type == "wait":
                normalized["ms"] = int(action.get("ms", 200))
            elif action_type in {"smart_guard", "smart_gather"}:
                pass
            elif action_type == "move_to":
                try:
                    normalized["x"] = float(action.get("x"))
                    normalized["y"] = float(action.get("y"))
                    normalized["z"] = float(action.get("z"))
                except Exception:
                    warnings.append(f"step {idx}: move_to invalid coords")
                    continue
            elif action_type == "pillar_up":
                steps_raw = action.get("steps", action.get("count", 1))
                try:
                    steps = int(steps_raw)
                except (TypeError, ValueError):
                    steps = 1
                normalized["steps"] = max(1, min(steps, 8))
            elif action_type == "go_to_player":
                target = (
                    action.get("player")
                    or action.get("player_name")
                    or action.get("name")
                    or action.get("target")
                )
                if target:
                    normalized["player"] = str(target)
                if action.get("distance") is not None:
                    try:
                        normalized["distance"] = float(action.get("distance"))
                    except Exception:
                        warnings.append(f"step {idx}: go_to_player invalid distance")
                        continue
                if action.get("timeout") is not None:
                    try:
                        normalized["timeout"] = float(action.get("timeout"))
                    except Exception:
                        warnings.append(f"step {idx}: go_to_player invalid timeout")
                        continue
            elif action_type == "go_to_nearest_block":
                block = action.get("block")
                blocks = action.get("blocks")
                if blocks is not None:
                    if not isinstance(blocks, list):
                        warnings.append(f"step {idx}: go_to_nearest_block blocks not list")
                        continue
                    normalized["blocks"] = [str(b) for b in blocks if b]
                if block:
                    normalized["block"] = str(block)
                if not normalized.get("block") and not normalized.get("blocks"):
                    warnings.append(f"step {idx}: go_to_nearest_block missing blocks")
                    continue
                if action.get("radius") is not None:
                    try:
                        normalized["radius"] = int(action.get("radius"))
                    except Exception:
                        warnings.append(f"step {idx}: go_to_nearest_block invalid radius")
                        continue
                if action.get("distance") is not None:
                    try:
                        normalized["distance"] = float(action.get("distance"))
                    except Exception:
                        warnings.append(f"step {idx}: go_to_nearest_block invalid distance")
                        continue
                if action.get("timeout") is not None:
                    try:
                        normalized["timeout"] = float(action.get("timeout"))
                    except Exception:
                        warnings.append(f"step {idx}: go_to_nearest_block invalid timeout")
                        continue
                if action.get("look_at") is not None:
                    normalized["look_at"] = bool(action.get("look_at"))
                if action.get("look_duration_ms") is not None:
                    try:
                        normalized["look_duration_ms"] = int(action.get("look_duration_ms"))
                    except Exception:
                        warnings.append(f"step {idx}: go_to_nearest_block invalid look_duration_ms")
                        continue
            elif action_type in {
                "open_container",
                "open_crafting_table",
                "open_furnace",
                "open_brewing_stand",
                "open_smithing_table",
                "open_enchanting_table",
                "open_trade",
                "collect_block",
            }:
                pass
            elif action_type == "alert_main_brain":
                msg = action.get("message") or action.get("msg") or ""
                normalized["message"] = str(msg)
            cleaned.append(normalized)
        return cleaned, warnings

    async def _run_llm_orchestrator_plan(
        self, goal: str, state: Dict[str, Any], params: Dict[str, Any]
    ) -> Dict[str, Any]:
        llm_cfg = self._resolve_llm_config(params)
        if not llm_cfg.get("ok"):
            return {
                "ok": False,
                "error": llm_cfg.get("error"),
                "actions": [],
                "planner": "llm_orchestrator",
            }
        api_key = llm_cfg.get("api_key")
        base_url = llm_cfg.get("base_url")
        model = llm_cfg.get("model")
        system_prompt = (
            "You are a Minecraft task orchestrator. "
            "Output JSON only with the schema: {\"actions\":[...],\"reason\":\"\"}. "
            "Choose only allowed actions. Keep steps minimal and safe. "
            "Avoid taking whole stacks if not needed. Prefer nearby containers/shulkers. "
            "Do not use ender_chest. If bed exists at night, sleep to set spawn. "
            "Use crafting grid appropriately (2x2 vs 3x3). If cursor holds item, store it first. "
            "If a required station or trade target is missing, alert_main_brain with context."
        )
        actions_spec = {
            "ensure_crafting_table": {},
            "ensure_furnace": {},
            "ensure_bed": {},
            "ensure_chest": {},
            "gather_item": {"item": "raw_gold", "count": 3},
            "smelt_output": {"item": "gold_ingot", "count": 3},
            "craft_item": {"item": "golden_axe", "count": 1},
            "brew_item": {"item": "awkward_potion", "count": 1},
            "smith_item": {"item": "netherite_sword", "count": 1},
            "enchant_item": {"item": "diamond_pickaxe", "count": 1},
            "trade_item": {"item": "emerald", "count": 5},
            "sleep": {},
            "follow_player": {"player": "player_name", "duration_sec": 20},
            "guard_player": {"player": "player_name", "duration_sec": 20},
            "smart_guard": {},
            "smart_gather": {},
            "store_inventory": {},
            "set_respawn": {},
            "move_to": {"x": 0, "y": 0, "z": 0},
            "go_to_player": {"player": "player_name"},
            "go_to_nearest_block": {"blocks": ["chest", "crafting_table"]},
            "pillar_up": {"steps": 2},
            "pickup_nearby": {},
            "open_container": {},
            "open_crafting_table": {},
            "open_furnace": {},
            "open_brewing_stand": {},
            "open_smithing_table": {},
            "open_enchanting_table": {},
            "open_trade": {},
            "collect_block": {"block": "log", "count": 1},
            "alert_main_brain": {"message": "text"},
            "close_screen": {},
            "wait": {"ms": 200},
        }
        user_payload = {
            "goal": goal,
            "state": state,
            "allowed_actions": actions_spec,
            "constraints": [
                "Avoid ender_chest.",
                "Prefer shulker boxes and nearby containers.",
                "Only take required items, do not loot all stacks.",
                "If a workstation is missing, ensure it by crafting/placing when possible.",
                "If it's night and a bed exists, use sleep to set spawn.",
                "For brewing/smithing/enchanting/trading, open the station first, then act.",
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
            return {
                "ok": False,
                "error": f"llm_error: {exc}",
                "actions": [],
                "planner": "llm_orchestrator",
            }
        plan = self._extract_json_object(response)
        if not plan:
            return {
                "ok": False,
                "error": "plan_parse_failed",
                "actions": [],
                "planner": "llm_orchestrator",
            }
        raw_actions = plan.get("actions")
        if not isinstance(raw_actions, list):
            return {
                "ok": False,
                "error": "plan_missing_actions",
                "actions": [],
                "planner": "llm_orchestrator",
            }
        actions, warnings = self._validate_orchestrator_actions(raw_actions)
        reason = plan.get("reason") if isinstance(plan.get("reason"), str) else None
        return {
            "ok": True,
            "actions": actions,
            "reason": reason,
            "warnings": warnings,
            "planner": "llm_orchestrator",
        }

    async def _execute_orchestrator_actions(
        self,
        actions: List[Dict[str, Any]],
        target_item: str,
        target_count: int,
        params: Dict[str, Any],
    ) -> Dict[str, Any]:
        steps: List[Dict[str, Any]] = []
        for idx, action in enumerate(actions):
            action_type = action.get("type")
            result: Dict[str, Any] = {"ok": False}
            if action_type == "ensure_crafting_table":
                result = await self.open_crafting_table(
                    {"radius": 8, "move": True, "place_if_missing": True}
                )
            elif action_type == "ensure_furnace":
                result = await self.open_furnace(
                    {
                        "radius": 8,
                        "move": True,
                        "craft_if_missing": True,
                        "take_furnace_from_containers": True,
                    }
                )
            elif action_type == "ensure_bed":
                result = await self._ensure_bed()
            elif action_type == "gather_item":
                result = await self.craft_from_container(
                    {
                        "item": action.get("item"),
                        "count": action.get("count", 1),
                        "skip_craft": True,
                        "open_table": False,
                        "smart_pickup": True,
                        "precise_pickup": True,
                        "multi_container": True,
                        "use_llm_orchestrator": False,
                        "_no_llm_orchestrator": True,
                    }
                )
            elif action_type == "smelt_output":
                result = await self._smelt_output_target(
                    str(action.get("item")), int(action.get("count", 1))
                )
            elif action_type == "craft_item":
                result = await self.craft_item(
                    {
                        "item": action.get("item"),
                        "count": action.get("count", 1),
                        "recursive": True,
                    }
                )
            elif action_type == "brew_item":
                result = await self.brew_item(
                    {
                        "item": action.get("item"),
                        "count": action.get("count", 1),
                        "use_rag": params.get("use_rag", True),
                        "use_mindcraft_docs": params.get("use_mindcraft_docs", True),
                        "rag_user_id": params.get("rag_user_id"),
                    }
                )
            elif action_type == "smith_item":
                result = await self.smith_item(
                    {
                        "item": action.get("item"),
                        "count": action.get("count", 1),
                        "use_rag": params.get("use_rag", True),
                        "use_mindcraft_docs": params.get("use_mindcraft_docs", True),
                        "rag_user_id": params.get("rag_user_id"),
                    }
                )
            elif action_type == "enchant_item":
                result = await self.enchant_item(
                    {
                        "item": action.get("item"),
                        "count": action.get("count", 1),
                        "use_rag": params.get("use_rag", True),
                        "use_mindcraft_docs": params.get("use_mindcraft_docs", True),
                        "rag_user_id": params.get("rag_user_id"),
                    }
                )
            elif action_type == "trade_item":
                result = await self.trade_item(
                    {
                        "item": action.get("item"),
                        "count": action.get("count", 1),
                        "use_rag": params.get("use_rag", True),
                        "use_mindcraft_docs": params.get("use_mindcraft_docs", True),
                        "rag_user_id": params.get("rag_user_id"),
                    }
                )
            elif action_type == "sleep":
                result = await self._sleep_in_bed()
            elif action_type == "follow_player":
                result = await self.follow_player(
                    {
                        "player_name": action.get("player"),
                        "duration_sec": action.get("duration_sec", 20.0),
                        "distance": 3.0,
                    }
                )
            elif action_type == "guard_player":
                result = await self.follow_player(
                    {
                        "player_name": action.get("player"),
                        "duration_sec": action.get("duration_sec", 20.0),
                        "distance": 2.5,
                    }
                )
            elif action_type == "smart_guard":
                result = await self.smart_guard({})
            elif action_type == "smart_gather":
                result = await self.smart_gather({})
            elif action_type == "ensure_chest":
                result = await self.open_container(
                    {"place_if_missing": True, "move": True, "radius": 6, "face": "up"}
                )
                if not result.get("ok"):
                    crafted = await self.craft_item(
                        {"item": "chest", "count": 1, "recursive": True}
                    )
                    if crafted.get("ok"):
                        result = await self.open_container(
                            {
                                "block": "chest",
                                "place_if_missing": True,
                                "move": True,
                                "radius": 6,
                                "face": "up",
                            }
                        )
            elif action_type == "store_inventory":
                result = await self.container_transfer(
                    {
                        "direction": "from_inventory",
                        "item": None,
                        "max_slots": 54,
                        "to_block": params.get("store_block"),
                        "place_if_missing": True,
                    }
                )
            elif action_type == "set_respawn":
                result = await self._sleep_in_bed()
            elif action_type == "move_to":
                result = await self.go_to_position(
                    {
                        "x": action.get("x"),
                        "y": action.get("y"),
                        "z": action.get("z"),
                        "distance": action.get("distance", 1.2),
                        "timeout": action.get("timeout", 8.0),
                    }
                )
            elif action_type == "pillar_up":
                result = await self.pillar_up(
                    {"steps": action.get("steps", action.get("count", 1))}
                )
            elif action_type == "pickup_nearby":
                result = await self.pickup_nearby_items(
                    {
                        "range": action.get("range", 8.0),
                        "timeout": action.get("timeout", 4.0),
                    }
                )
            elif action_type == "open_container":
                result = await self.open_container(
                    {
                        "block": action.get("block"),
                        "blocks": action.get("blocks"),
                        "radius": action.get("radius", 6),
                        "move": True,
                        "place_if_missing": True,
                    }
                )
            elif action_type == "open_crafting_table":
                result = await self.open_crafting_table(
                    {"radius": action.get("radius", 6), "move": True, "place_if_missing": True}
                )
            elif action_type == "open_furnace":
                result = await self.open_furnace(
                    {"radius": action.get("radius", 6), "move": True, "craft_if_missing": False}
                )
            elif action_type == "open_brewing_stand":
                result = await self.open_brewing_stand(
                    {"radius": action.get("radius", 6), "move": True}
                )
            elif action_type == "open_smithing_table":
                result = await self.open_smithing_table(
                    {"radius": action.get("radius", 6), "move": True}
                )
            elif action_type == "open_enchanting_table":
                result = await self.open_enchanting_table(
                    {"radius": action.get("radius", 6), "move": True}
                )
            elif action_type == "open_trade":
                result = await self.open_trade(
                    {"radius": action.get("radius", 6), "move": True}
                )
            elif action_type == "collect_block":
                result = await self.collect_block(
                    {
                        "block": action.get("block"),
                        "count": action.get("count", 1),
                        "radius": action.get("radius", 6),
                    }
                )
            elif action_type == "alert_main_brain":
                message = action.get("message") or action.get("msg") or ""
                if message:
                    await self._emit_alert(
                        str(message),
                        {"source": "llm_orchestrator", "action": action},
                    )
                result = {"ok": True}
            elif action_type == "close_screen":
                await self._adapter.send_action(
                    {"type": "closeScreen"}, self._headful_config()
                )
                result = {"ok": True}
            elif action_type == "wait":
                await asyncio.sleep(max(0, int(action.get("ms", 200))) / 1000.0)
                result = {"ok": True}
            steps.append({"step": action, "result": result})
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot and self._inventory_has_item(snapshot, target_item, target_count):
                return {"ok": True, "steps": steps, "completed": True}
            if not result.get("ok"):
                return {"ok": False, "steps": steps, "failed_step": idx}
        return {"ok": False, "steps": steps, "completed": False}

    async def _llm_orchestrate_craft(self, params: Dict[str, Any]) -> Dict[str, Any]:
        item_name = _normalize_item_name(params.get("item"))
        count = int(params.get("count", 1))
        if not item_name:
            return {"ok": False, "error": "missing_item"}
        max_rounds = int(params.get("llm_rounds", 2))
        allow_smelting = bool(params.get("allow_smelting", True))
        last_error: Optional[Dict[str, Any]] = None
        for round_idx in range(max_rounds):
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot is None:
                break
            inventory = self._inventory_counts(snapshot)
            graph = self._get_resource_graph()
            plan_graph = graph.plan(
                item_name, count, dict(inventory), allow_smelting=allow_smelting
            )
            state = self._state_summary_for_llm(plan_graph=plan_graph)
            state["inventory"] = inventory
            state["round"] = round_idx
            goal = params.get("goal") or f"craft {item_name} x{count}"
            llm_plan = await self._run_llm_orchestrator_plan(goal, state, params)
            if not llm_plan.get("ok") or not llm_plan.get("actions"):
                last_error = llm_plan
                break
            exec_result = await self._execute_orchestrator_actions(
                llm_plan.get("actions") or [],
                item_name,
                count,
                params,
            )
            if exec_result.get("ok"):
                return {
                    "ok": True,
                    "planner": "llm_orchestrator",
                    "plan": llm_plan,
                    "steps": exec_result.get("steps", []),
                }
            last_error = exec_result
        fallback = await self.craft_from_container(
            {**params, "use_llm_orchestrator": False, "_no_llm_orchestrator": True}
        )
        if last_error:
            fallback["llm_error"] = last_error
        return fallback

    async def smart_guard(self, params: Dict[str, Any]) -> Dict[str, Any]:
        cfg = self._headful_config()
        if not bool(cfg.get("enable_smart_guard", True)):
            return {"ok": False, "error": "smart_guard_disabled"}
        player_name = params.get("player") or params.get("player_name")
        threat = self._select_nearest_hostile_entity(
            max_distance_sq=(params.get("range", 12.0) ** 2)
        )
        if threat:
            etype = str(threat.get("type", "")).split(":")[-1]
            return await self.attack_nearest(
                {
                    "entity_type": etype,
                    "duration_sec": params.get("duration_sec", 12.0),
                    "range": params.get("range", 12.0),
                }
            )
        if player_name:
            return await self.follow_player(
                {
                    "player_name": player_name,
                    "duration_sec": params.get("duration_sec", 12.0),
                    "distance": params.get("distance", 3.0),
                }
            )
        # 没有威胁时轻度巡逻/防御
        return await self.defend_self(
            {
                "range": params.get("range", 12.0),
                "duration_sec": params.get("duration_sec", 12.0),
            }
        )

    async def smart_gather(self, params: Dict[str, Any]) -> Dict[str, Any]:
        cfg = self._headful_config()
        if not bool(cfg.get("enable_smart_gather", True)):
            return {"ok": False, "error": "smart_gather_disabled"}
        # 先捡掉落物
        result = await self.pickup_nearby_items(
            {
                "range": params.get("range", 10.0),
                "timeout": params.get("timeout", 6.0),
            }
        )
        if result.get("ok"):
            return result
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        available = self._inventory_counts(snapshot) if snapshot else {}
        fuel_total = sum(available.get(item, 0) for item in FUEL_PRIORITY)
        log_total = sum(
            count
            for name, count in available.items()
            if name.endswith("_log") or name.endswith("_wood")
        )
        plank_total = sum(
            count for name, count in available.items() if name.endswith("_planks")
        )
        min_fuel = int(params.get("min_fuel", 2))
        min_wood = int(params.get("min_wood", 4))
        if fuel_total < min_fuel:
            block = params.get("fuel_block", "log")
            count = int(params.get("fuel_count", 4))
            return await self.collect_block(
                {"block": block, "count": count, "radius": params.get("radius", 8)}
            )
        if log_total + plank_total < min_wood:
            block = params.get("wood_block", "log")
            count = int(params.get("wood_count", 4))
            return await self.collect_block(
                {"block": block, "count": count, "radius": params.get("radius", 8)}
            )
        # 默认采集基础方块（避免空转）
        block = params.get("block", "log")
        count = int(params.get("count", 4))
        return await self.collect_block(
            {"block": block, "count": count, "radius": params.get("radius", 8)}
        )

    async def _run_llm_plan(
        self,
        goal: str,
        snapshot: ScreenSnapshot,
        params: Dict[str, Any],
    ) -> Dict[str, Any]:
        cfg = self._config()
        llm_cfg = self._resolve_llm_config(params)
        if not llm_cfg.get("ok"):
            return {
                "ok": False,
                "error": llm_cfg.get("error"),
                "actions": [],
                "planner": "llm",
            }
        api_key = llm_cfg.get("api_key")
        base_url = llm_cfg.get("base_url")
        model = llm_cfg.get("model")
        embedding_api_key = params.get("embedding_api_key")
        embedding_base_url = params.get("embedding_base_url")
        embedding_model = params.get("embedding_model")
        user_id = (
            params.get("rag_user_id")
            or cfg.get("rag_user_id")
            or cfg.get("agent_name")
            or "minecraft"
        )
        use_rag = bool(params.get("use_rag", True))
        use_mindcraft_docs = bool(params.get("use_mindcraft_docs", False))
        scopes = ["long_term"]
        if use_mindcraft_docs:
            scopes.append("knowledge")
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
                    embedding_api_key=embedding_api_key,
                    embedding_base_url=embedding_base_url,
                    embedding_model=embedding_model,
                    scopes=scopes,
                    fast_mode=True,
                )
            except Exception:
                rag_context = ""

        system_prompt = (
            "You are a Minecraft GUI action planner. "
            "Output JSON only with the schema: {\"actions\":[...],\"reason\":\"\"}. "
            "Use only allowed actions. If unsure, return empty actions with a reason. "
            "Prefer minimal clicks and avoid taking more items than needed. "
            "Do not use ender_chest. Prefer shulker boxes, chests nearby. "
            "If cursor holds item, place it into inventory first. "
            "Use crafting grid slots from snapshot; if grid is 2x2, only craft simple recipes."
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
        self._cancel_requested = False
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

        planner_mode = (params.get("planner_mode") or params.get("planner") or "").strip().lower()
        if planner_mode in {"rules_only", "rules", "no_llm"} and selected is None:
            text_plan = self._plan_text_only(goal, available)
            if text_plan:
                return {
                    "ok": True,
                    "actions": [],
                    "reason": text_plan.get("reason"),
                    "warnings": [],
                    "planner": text_plan.get("planner"),
                    "plan_text": text_plan.get("plan_text"),
                    "trace": plan_trace,
                }
            return {"ok": False, "error": "rules_plan_not_found", "trace": plan_trace}

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
        auto_substeps = None
        auto_error = None
        if execute and not actions_list and plan_text:
            auto_craft_result = None
            if self._goal_is_craft(goal) and not self._goal_is_crafting_table(goal):
                item_name = self._extract_item_from_goal(goal)
                if item_name:
                    auto_craft_result = await self.craft_item(
                        {
                            "item": item_name,
                            "count": int(params.get("count", 1) or 1),
                            "recursive": True,
                            "auto_gather_base_items": True,
                            "auto_open_crafting_table": True,
                        },
                        execute=True,
                    )
                    if auto_craft_result.get("ok"):
                        self._log_append(f"[auto-craft] ok: {item_name}")
                    else:
                        self._log_append(
                            f"[auto-craft] failed: {item_name} err={auto_craft_result.get('error')}"
                        )
                    auto_substeps = [{"step": "auto_craft", "result": auto_craft_result}]
                    if auto_craft_result.get("ok"):
                        plan_payload["auto_substeps"] = auto_substeps
                        self.last_plan = plan_payload
                        return {
                            "ok": True,
                            "actions": actions_list,
                            "executed": 0,
                            "reason": reason,
                            "warnings": warnings_list,
                            "planner": planner,
                            "plan_text": plan_text,
                            "trace": plan_trace,
                            "auto_substeps": auto_substeps,
                        }
                    auto_error = auto_craft_result.get("error")

            if auto_substeps is not None:
                plan_payload["auto_substeps"] = auto_substeps
            if auto_error:
                plan_payload["auto_error"] = auto_error
            self.last_plan = plan_payload

            lines = [line.strip() for line in plan_text.splitlines() if line.strip()]
            preview = "\n".join(lines[:6]) if lines else plan_text
            await self._emit_alert(
                f"无法执行：{goal}\n{preview}",
                {"goal": goal, "planner": planner, "reason": reason},
            )

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
            if self._cancel_requested:
                self._cancel_requested = False
                return {
                    "ok": False,
                    "error": "cancelled",
                    "actions": actions_list,
                    "executed": executed,
                    "reason": reason,
                    "warnings": warnings_list,
                    "planner": planner,
                    "plan_text": plan_text,
                    "trace": plan_trace,
                }

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
            non_player = [
                slot
                for slot in slots
                if slot.group
                not in {
                    "player_main",
                    "player_hotbar",
                    "player_armor",
                    "player_offhand",
                }
            ]
            if 4 <= len(non_player) <= 10:
                xs = sorted({slot.x for slot in non_player})
                max_x = max(xs) if xs else None
                if max_x is not None:
                    col_slots = [slot for slot in non_player if slot.x == max_x]
                    if len(col_slots) == 1 and (len(non_player) - 1) in {4, 9}:
                        non_player = [slot for slot in non_player if slot.x != max_x]
                craft_slots = [slot for slot in non_player]
        if not craft_slots:
            return None
        xs = sorted({slot.x for slot in craft_slots})
        ys = sorted({slot.y for slot in craft_slots})
        grid: Dict[Tuple[int, int], SlotInfo] = {}
        for slot in craft_slots:
            grid[(xs.index(slot.x), ys.index(slot.y))] = slot
        return grid, len(xs), len(ys)

    def _infer_crafting_output(
        self,
        snapshot: ScreenSnapshot,
        grid: Dict[Tuple[int, int], SlotInfo],
    ) -> Optional[SlotInfo]:
        grid_slots = {slot.slot for slot in grid.values()}
        candidates = [
            slot
            for slot in snapshot.slots
            if slot.slot not in grid_slots
            and slot.group
            not in {"player_main", "player_hotbar", "player_armor", "player_offhand"}
        ]
        if not candidates:
            return None
        if len(candidates) == 1:
            return candidates[0]
        candidates.sort(key=lambda slot: (slot.x, slot.y))
        return candidates[-1]

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

    def _potential_count(
        self,
        item_name: str,
        available: Dict[str, int],
        depth: int = 0,
        chain: Optional[set[str]] = None,
    ) -> int:
        base = available.get(item_name, 0)
        if depth > 3:
            return base
        if chain is None:
            chain = set()
        if item_name in chain:
            return base
        next_chain = set(chain)
        next_chain.add(item_name)
        recipe_book = self._get_recipe_book()
        recipes = recipe_book.get_recipes(item_name)
        best = 0
        for recipe in recipes:
            requirements = self._recipe_requirements(recipe)
            if not requirements:
                continue
            craftable = min(
                self._potential_count(req_item, available, depth + 1, next_chain)
                // req_count
                for req_item, req_count in requirements.items()
            )
            produced = craftable * max(recipe.result_count, 1)
            if produced > best:
                best = produced
        return base + best

    def _select_recipe(
        self, recipes: List[Recipe], available: Dict[str, int]
    ) -> Optional[Recipe]:
        if not recipes:
            return None
        best_recipe = None
        best_score = -1
        for recipe in recipes:
            craftable = self._max_craftable(recipe, available)
            if craftable > 0:
                score = craftable * 1000 + max(recipe.result_count, 1)
            else:
                requirements = self._recipe_requirements(recipe)
                if not requirements:
                    score = 0
                else:
                    potential = min(
                        self._potential_count(req_item, available) // req_count
                        for req_item, req_count in requirements.items()
                    )
                    score = potential
            if score > best_score:
                best_score = score
                best_recipe = recipe
        return best_recipe

    def _recipe_fits(self, recipe: Recipe, width: int, height: int) -> bool:
        if recipe.shaped and recipe.shape:
            rh = len(recipe.shape)
            rw = max((len(row) for row in recipe.shape), default=0)
            return rh <= height and rw <= width
        if recipe.ingredients:
            return len(recipe.ingredients) <= width * height
        return False

    def _recipe_required_grid(self, recipe: Recipe) -> Tuple[int, int]:
        if recipe.shaped and recipe.shape:
            rh = len(recipe.shape)
            rw = max((len(row) for row in recipe.shape), default=0)
            return rw, rh
        if recipe.ingredients:
            count = len(recipe.ingredients)
            if count <= 1:
                return 1, 1
            if count <= 4:
                return 2, 2
            return 3, 3
        return 0, 0

    def _recipe_requires_table(self, recipe: Recipe) -> bool:
        width, height = self._recipe_required_grid(recipe)
        return width > 2 or height > 2

    def _recipes_require_table(self, recipes: List[Recipe]) -> bool:
        if not recipes:
            return False
        return all(self._recipe_requires_table(recipe) for recipe in recipes)

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
        for cn, item in sorted(CN_ITEM_ALIASES.items(), key=lambda entry: len(entry[0]), reverse=True):
            if cn in goal and recipe_book.has_item(item):
                return item
        return None

    def _is_base_item(self, item_name: str) -> bool:
        if self._is_smelt_output(item_name):
            return False
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

        recipes_for_target = recipe_book.get_recipes(target_item)
        requires_table = self._recipes_require_table(recipes_for_target)
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
        if requires_table:
            lines.append("Note: This recipe requires a crafting table (3x3).")
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

    def _extract_coords_from_goal(self, goal: str) -> Optional[Tuple[float, float, float]]:
        raw = (goal or "").lower()
        x_match = re.search(r"x\s*[:=]?\s*(-?\d+(?:\.\d+)?)", raw)
        y_match = re.search(r"y\s*[:=]?\s*(-?\d+(?:\.\d+)?)", raw)
        z_match = re.search(r"z\s*[:=]?\s*(-?\d+(?:\.\d+)?)", raw)
        if x_match and y_match and z_match:
            return (
                float(x_match.group(1)),
                float(y_match.group(1)),
                float(z_match.group(1)),
            )
        triple = re.search(r"(-?\d+(?:\.\d+)?)\s*[ ,/]\s*(-?\d+(?:\.\d+)?)\s*[ ,/]\s*(-?\d+(?:\.\d+)?)", raw)
        if triple:
            return (
                float(triple.group(1)),
                float(triple.group(2)),
                float(triple.group(3)),
            )
        return None

    def _extract_two_coords_from_goal(
        self, goal: str
    ) -> Optional[Tuple[Tuple[float, float, float], Tuple[float, float, float]]]:
        raw = goal or ""
        parts = re.split(r"\s*(?:到|至|to|->|~|—)\s*", raw, maxsplit=1, flags=re.I)
        if len(parts) == 2:
            first = self._extract_coords_from_goal(parts[0])
            second = self._extract_coords_from_goal(parts[1])
            if first and second:
                return first, second
        triples = re.findall(
            r"(-?\d+(?:\.\d+)?)\s*[ ,/]\s*(-?\d+(?:\.\d+)?)\s*[ ,/]\s*(-?\d+(?:\.\d+)?)",
            raw,
        )
        if len(triples) >= 2:
            first = triples[0]
            second = triples[1]
            return (
                (float(first[0]), float(first[1]), float(first[2])),
                (float(second[0]), float(second[1]), float(second[2])),
            )
        return None

    def _extract_fill_walls_flag(self, goal: str) -> Optional[bool]:
        raw = (goal or "").lower()
        match = re.search(
            r"(?:fill_wall|fillwalls|fillwall|补墙|填墙|封墙|补边|填边|封边)\s*[:=]?\s*(true|false|1|0|on|off|是|否|开|关)",
            raw,
        )
        if match:
            token = match.group(1)
            if token in {"true", "1", "on", "是", "开"}:
                return True
            if token in {"false", "0", "off", "否", "关"}:
                return False
        if any(
            phrase in raw
            for phrase in (
                "不补墙",
                "不要补墙",
                "不填墙",
                "不要填墙",
                "no wall",
                "no_wall",
            )
        ):
            return False
        if any(
            phrase in raw
            for phrase in (
                "补墙",
                "填墙",
                "封墙",
                "补边",
                "填边",
                "封边",
                "fillwall",
                "fill_wall",
                "fill walls",
            )
        ):
            return True
        return None

    def _extract_step_count(self, goal: str, default: int = 2) -> int:
        raw = goal or ""
        match = re.search(r"(\d+)", raw)
        if match:
            try:
                value = int(match.group(1))
                return max(1, min(value, 8))
            except ValueError:
                pass
        cn_map = {
            "一": 1,
            "二": 2,
            "两": 2,
            "三": 3,
            "四": 4,
            "五": 5,
            "六": 6,
            "七": 7,
            "八": 8,
        }
        for cn, value in cn_map.items():
            if cn in raw:
                return value
        return default

    def _extract_player_from_goal(self, goal: str) -> Optional[str]:
        raw = goal or ""
        match = re.search(r"(?:跟随|跟着|跟我|follow)\s*([A-Za-z0-9_]+)", raw, re.I)
        if match:
            return match.group(1)
        match = re.search(r"(?:玩家|player)\s*([A-Za-z0-9_]+)", raw, re.I)
        if match:
            return match.group(1)
        match = re.search(r"(?:找|寻找|去找|找到|靠近)\s*([A-Za-z0-9_]+)", raw, re.I)
        if match:
            return match.group(1)
        return None

    def _extract_entity_from_goal(self, goal: str) -> Optional[str]:
        raw = (goal or "").lower()
        cn_map = {
            "僵尸": "zombie",
            "骷髅": "skeleton",
            "苦力怕": "creeper",
            "蜘蛛": "spider",
            "洞穴蜘蛛": "cave_spider",
            "末影人": "enderman",
            "女巫": "witch",
            "史莱姆": "slime",
            "岩浆怪": "magma_cube",
            "掠夺者": "pillager",
            "卫道士": "vindicator",
            "唤魔者": "evoker",
            "劫掠兽": "ravager",
            "幻翼": "phantom",
            "守卫者": "guardian",
            "远古守卫者": "elder_guardian",
            "猪灵": "piglin",
            "僵尸猪灵": "zombified_piglin",
            "猪灵蛮兵": "piglin_brute",
            "溺尸": "drowned",
            "僵尸村民": "zombie_villager",
            "女巫": "witch",
            "凋灵骷髅": "wither_skeleton",
        }
        for cn, en in cn_map.items():
            if cn in goal:
                return en
        for etype in HOSTILE_ENTITY_TYPES:
            if etype in raw:
                return etype
        return None

    def _unique_targets(self, items: List[str]) -> List[str]:
        seen: set[str] = set()
        result: List[str] = []
        for item in items:
            key = _normalize_item_name(item)
            if not key or key in seen:
                continue
            seen.add(key)
            result.append(key)
        return result

    def _filter_block_targets(self, blocks: List[str], cfg: Dict[str, Any]) -> List[str]:
        deny_raw = cfg.get("container_denylist")
        if deny_raw is None:
            deny_raw = ["ender_chest"]
        if isinstance(deny_raw, str):
            deny_list = [deny_raw]
        elif isinstance(deny_raw, list):
            deny_list = [str(item) for item in deny_raw if item]
        else:
            deny_list = []
        deny_set = {self._normalize_block_name(item).split(":", 1)[1] for item in deny_list}
        if not deny_set:
            return blocks
        filtered = []
        for block in blocks:
            name = self._normalize_block_name(block).split(":", 1)[1]
            if name in deny_set:
                continue
            filtered.append(block)
        return filtered

    def _extract_block_targets_from_goal(self, goal: str) -> List[str]:
        targets: List[str] = []
        raw = goal or ""
        lowered = raw.lower()

        if any(keyword in raw for keyword in ("工作方块", "工作站")):
            targets.extend(sorted(BASIC_UTILITY_BLOCKS))

        if any(keyword in raw for keyword in ("箱子", "储物箱", "箱", "容器")):
            targets.extend(["chest", "barrel", "shulker_box", "trapped_chest"])
        if "木桶" in raw:
            targets.append("barrel")
        if "潜影盒" in raw:
            targets.append("shulker_box")
        if "末影箱" in raw or "ender chest" in lowered:
            targets.append("ender_chest")

        if "工作台" in raw or "工作桌" in raw or "crafting table" in lowered:
            targets.append("crafting_table")
        if "熔炉" in raw or "炉子" in raw:
            targets.append("furnace")
        if "高炉" in raw or "blast furnace" in lowered:
            targets.append("blast_furnace")
        if "烟熏炉" in raw or "smoker" in lowered:
            targets.append("smoker")
        if "酿造台" in raw or "brewing" in lowered:
            targets.append("brewing_stand")
        if "附魔台" in raw or "enchant" in lowered:
            targets.append("enchanting_table")
        if "锻造台" in raw or "smithing" in lowered:
            targets.append("smithing_table")
        if "铁砧" in raw or "anvil" in lowered:
            targets.append("anvil")
        if "砂轮" in raw or "磨石" in raw or "grindstone" in lowered:
            targets.append("grindstone")
        if "切石机" in raw or "stonecutter" in lowered:
            targets.append("stonecutter")
        if "织布机" in raw or "loom" in lowered:
            targets.append("loom")
        if "制图台" in raw or "cartography" in lowered:
            targets.append("cartography_table")
        if "讲台" in raw or "lectern" in lowered:
            targets.append("lectern")
        if "堆肥桶" in raw or "composter" in lowered:
            targets.append("composter")
        if "发射器" in raw or "dispenser" in lowered:
            targets.append("dispenser")
        if "投掷器" in raw or "dropper" in lowered:
            targets.append("dropper")
        if "漏斗" in raw or "hopper" in lowered:
            targets.append("hopper")

        return self._unique_targets(targets)

    def _goal_has_move_intent(self, goal: str) -> bool:
        lowered = (goal or "").lower()
        keywords = (
            "移动",
            "前往",
            "走到",
            "去",
            "到",
            "靠近",
            "附近",
            "寻找",
            "找",
            "move",
            "goto",
            "go to",
            "near",
            "closest",
            "find",
        )
        return any(keyword in lowered or keyword in goal for keyword in keywords)

    def _plan_dig_area_from_goal(self, goal: str) -> Optional[Dict[str, Any]]:
        lowered = (goal or "").lower()
        if not any(
            keyword in lowered or keyword in goal
            for keyword in ("挖", "挖掘", "挖空", "清空", "dig", "excavate")
        ):
            return None
        coords = self._extract_two_coords_from_goal(goal)
        if not coords:
            return None
        fill_walls = self._extract_fill_walls_flag(goal)
        (x1, y1, z1), (x2, y2, z2) = coords
        return {
            "ok": True,
            "actions": [
                {
                    "type": "dig_area",
                    "x1": x1,
                    "y1": y1,
                    "z1": z1,
                    "x2": x2,
                    "y2": y2,
                    "z2": z2,
                    "fill_walls": fill_walls,
                }
            ],
            "reason": "dig_area",
            "planner": "rules:dig_area",
        }

    def _plan_move_from_goal(self, goal: str) -> Optional[Dict[str, Any]]:
        lowered = (goal or "").lower()
        if any(
            keyword in goal
            for keyword in (
                "垫脚",
                "垫高",
                "垒方块",
                "搭方块",
                "堆方块",
                "搭高",
                "爬高",
                "爬上",
                "向上",
            )
        ):
            steps = self._extract_step_count(goal, default=2)
            return {
                "ok": True,
                "actions": [{"type": "pillar_up", "steps": steps}],
                "reason": "pillar_up",
                "planner": "rules:move",
                "plan_text": None,
                "warnings": [],
            }
        if any(keyword in lowered for keyword in ("move", "goto", "go to", "前往", "移动", "走到", "去")):
            coords = self._extract_coords_from_goal(goal)
            if coords:
                return {
                    "ok": True,
                    "actions": [
                        {"type": "move_to", "x": coords[0], "y": coords[1], "z": coords[2]}
                    ],
                    "reason": "move_to_coords",
                    "planner": "rules:move",
                    "plan_text": None,
                    "warnings": [],
                }
        if any(keyword in goal for keyword in ("跟随", "跟着", "follow")):
            player = self._extract_player_from_goal(goal)
            return {
                "ok": True,
                "actions": [{"type": "follow_player", "player": player}],
                "reason": "follow_player",
                "planner": "rules:follow",
                "plan_text": None,
                "warnings": [],
            }
        player = self._extract_player_from_goal(goal)
        if (player or "玩家" in goal or "player" in lowered) and self._goal_has_move_intent(goal):
            return {
                "ok": True,
                "actions": [{"type": "go_to_player", "player": player}],
                "reason": "go_to_player",
                "planner": "rules:move",
                "plan_text": None,
                "warnings": [],
            }
        targets = self._extract_block_targets_from_goal(goal)
        if targets and self._goal_has_move_intent(goal):
            cfg = self._headful_config()
            targets = self._filter_block_targets(targets, cfg)
            if targets:
                return {
                    "ok": True,
                    "actions": [
                        {
                            "type": "go_to_nearest_block",
                            "blocks": targets,
                            "radius": int(cfg.get("scan_radius", 16)),
                        }
                    ],
                    "reason": "go_to_block",
                    "planner": "rules:move",
                    "plan_text": None,
                    "warnings": [],
                }
        return None

    def _plan_combat_from_goal(self, goal: str) -> Optional[Dict[str, Any]]:
        if any(keyword in goal for keyword in ("护卫", "守护", "保护")):
            return {
                "ok": True,
                "actions": [{"type": "smart_guard"}],
                "reason": "smart_guard",
                "planner": "rules:combat",
                "plan_text": None,
                "warnings": [],
            }
        if any(keyword in goal for keyword in ("攻击", "战斗", "打怪", "消灭")):
            entity = self._extract_entity_from_goal(goal)
            if entity:
                return {
                    "ok": True,
                    "actions": [{"type": "attack_nearest", "entity_type": entity}],
                    "reason": "attack_nearest",
                    "planner": "rules:combat",
                    "plan_text": None,
                    "warnings": [],
                }
            return {
                "ok": True,
                "actions": [{"type": "defend_self"}],
                "reason": "defend_self",
                "planner": "rules:combat",
                "plan_text": None,
                "warnings": [],
            }
        return None

    def _plan_place_from_goal(self, goal: str) -> Optional[Dict[str, Any]]:
        if not any(keyword in goal for keyword in ("放置", "放下", "摆放", "放个", "放一个", "place")):
            return None
        item = self._extract_item_from_goal(goal)
        if item:
            return {
                "ok": True,
                "actions": [{"type": "place_block", "block": item}],
                "reason": "place_block",
                "planner": "rules:place",
                "plan_text": None,
                "warnings": [],
            }
        return {
            "ok": True,
            "actions": [{"type": "useTarget"}],
            "reason": "use_target",
            "planner": "rules:place",
            "plan_text": None,
            "warnings": [],
        }

    async def _plan_from_rules(
        self,
        goal: str,
        snapshot: ScreenSnapshot,
        available: Dict[str, int],
    ) -> Optional[Dict[str, Any]]:
        dig_plan = self._plan_dig_area_from_goal(goal)
        if dig_plan:
            return dig_plan
        move_plan = self._plan_move_from_goal(goal)
        if move_plan:
            return move_plan
        combat_plan = self._plan_combat_from_goal(goal)
        if combat_plan:
            return combat_plan
        place_plan = self._plan_place_from_goal(goal)
        if place_plan:
            return place_plan
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

    def _log_block_variants(self) -> List[str]:
        recipe_book = self._get_recipe_book()
        try:
            items = recipe_book.all_items()
        except Exception:
            items = []
        logs = [item for item in items if self._is_log(item)]
        if not logs:
            logs = [
                "oak_log",
                "spruce_log",
                "birch_log",
                "jungle_log",
                "acacia_log",
                "dark_oak_log",
                "mangrove_log",
                "cherry_log",
                "crimson_stem",
                "warped_stem",
            ]
        return sorted(set(logs))

    def _tool_type_for_block(self, block_name: str) -> Optional[str]:
        if not block_name:
            return None
        name = self._normalize_block_name(block_name).split(":", 1)[-1]
        if self._is_log(name) or name.endswith("_planks"):
            return "axe"
        if (
            "ore" in name
            or name
            in {
                "stone",
                "cobblestone",
                "deepslate",
                "cobbled_deepslate",
                "andesite",
                "diorite",
                "granite",
                "tuff",
                "calcite",
                "netherrack",
                "basalt",
                "blackstone",
                "end_stone",
                "obsidian",
            }
        ):
            return "pickaxe"
        if name in {
            "dirt",
            "grass_block",
            "coarse_dirt",
            "podzol",
            "rooted_dirt",
            "sand",
            "red_sand",
            "gravel",
            "clay",
            "snow",
            "snow_block",
            "soul_sand",
            "soul_soil",
            "farmland",
            "mud",
        }:
            return "shovel"
        return None

    def _tool_type_for_blocks(self, block_names: Iterable[str]) -> Optional[str]:
        tool = None
        for block_name in block_names:
            candidate = self._tool_type_for_block(block_name)
            if candidate == "pickaxe":
                return "pickaxe"
            if candidate == "axe" and tool != "pickaxe":
                tool = "axe"
            if candidate == "shovel" and tool is None:
                tool = "shovel"
        return tool

    def _best_tool_name(self, snapshot: ScreenSnapshot, tool_type: str) -> Optional[str]:
        candidates = TOOL_CANDIDATES.get(tool_type, [])
        for name in candidates:
            if self._inventory_has_item(snapshot, name, 1):
                return name
        return None

    async def _auto_gather_missing_base_items(
        self, missing: Dict[str, int], params: Dict[str, Any]
    ) -> Dict[str, Any]:
        cfg = self._headful_config()
        if "auto_gather_base_items" in params:
            enabled = bool(params.get("auto_gather_base_items"))
        else:
            enabled = bool(cfg.get("auto_gather_base_items", False))
        if not enabled:
            return {"ok": False, "error": "auto_gather_disabled"}
        try:
            radius = int(params.get("auto_gather_radius", cfg.get("auto_gather_radius", 12)))
        except (TypeError, ValueError):
            radius = 12
        radius = max(3, radius)
        results: List[Dict[str, Any]] = []
        gathered_any = False
        use_containers = bool(
            params.get(
                "auto_collect_from_containers",
                cfg.get("auto_collect_from_containers", True),
            )
        )
        for item, count in missing.items():
            if not item or count <= 0:
                continue
            blocks: List[str] = []
            gather_count = max(1, int(count))
            remaining = gather_count
            if use_containers:
                container_result = await self.craft_from_container(
                    {
                        "item": item,
                        "count": gather_count,
                        "skip_craft": True,
                        "smart_pickup": True,
                        "move": True,
                        "container_radius": params.get(
                            "container_radius",
                            cfg.get("container_radius_default", 5),
                        ),
                        "container_timeout": params.get(
                            "container_timeout", params.get("timeout", 4.0)
                        ),
                        "container_search_radii": params.get(
                            "container_search_radii", cfg.get("container_search_radii")
                        ),
                    }
                )
                results.append({"item": item, "need": gather_count, "container": container_result})
                if container_result.get("ok"):
                    remaining_map = container_result.get("remaining")
                    if isinstance(remaining_map, dict):
                        remaining = int(remaining_map.get(item, 0) or 0)
                    if remaining < gather_count:
                        gathered_any = True
                    if remaining <= 0:
                        gathered_any = True
                        continue
            if self._is_log(item):
                blocks = [item]
            elif item == "cobblestone":
                blocks = ["cobblestone", "stone"]
            elif item == "stone":
                blocks = ["stone"]
            elif item == "cobbled_deepslate":
                blocks = ["cobbled_deepslate", "deepslate"]
            elif item.endswith("_planks"):
                blocks = self._log_block_variants()
                gather_count = max(1, int(math.ceil(remaining / 4)))
            else:
                results.append({"item": item, "ok": False, "error": "unsupported_base"})
                continue
            result = await self.collect_block(
                {
                    "blocks": blocks,
                    "count": gather_count,
                    "radius": radius,
                    "auto_equip_tool": True,
                }
            )
            results.append({"item": item, "need": count, "gather": result})
            if result.get("ok"):
                gathered_any = True
        if gathered_any:
            self._log_append(f"[auto-gather] gathered base items: {list(missing.keys())}")
        return {"ok": gathered_any, "results": results}

    def _is_smelt_output(self, item_name: str) -> bool:
        return item_name in SMELTING_OUTPUTS or item_name in SMELT_LOG_OUTPUTS

    def _select_smelt_input(
        self, output_item: str, available: Dict[str, int]
    ) -> Optional[str]:
        candidates = SMELTING_OUTPUTS.get(output_item)
        if candidates:
            for name in candidates:
                if available.get(name, 0) > 0:
                    return name
            return candidates[0] if candidates else None
        if output_item in SMELT_LOG_OUTPUTS:
            for name, count in available.items():
                if count > 0 and self._is_log(name):
                    return name
        return None

    def _select_fuel_item(self, available: Dict[str, int]) -> Optional[str]:
        for fuel in FUEL_PRIORITY:
            if available.get(fuel, 0) > 0:
                return fuel
        for name, count in available.items():
            if count <= 0:
                continue
            if self._is_log(name) or self._is_planks(name) or name == "stick":
                return name
        return None

    def _clear_cursor_actions(
        self, snapshot: ScreenSnapshot
    ) -> Tuple[Optional[List[Dict[str, Any]]], Optional[str]]:
        if not snapshot.cursor:
            return [], None
        target_slots = self._slots_by_group(
            snapshot.slots, ("player_main", "player_hotbar")
        )
        target = next(
            (
                slot
                for slot in target_slots
                if slot.item
                and slot.item.name == snapshot.cursor.name
                and slot.item.count < slot.item.max_count
            ),
            None,
        )
        if target is None:
            target = next((slot for slot in target_slots if slot.item is None), None)
        if not target:
            return None, "cursor_blocked"
        return (
            [{"type": "clickSlot", "slot": target.slot, "button": 0, "action": "pickup"}],
            None,
        )

    async def _smelt_input(
        self,
        input_item: str,
        count: int,
        expected_output: Optional[str] = None,
        timeout_sec: float = 30.0,
    ) -> Dict[str, Any]:
        if not input_item:
            return {"ok": False, "error": "missing_item"}
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        if snapshot is None:
            return {"ok": False, "error": "no_snapshot"}
        input_slot = next(
            (slot for slot in snapshot.slots if slot.group == "container_input"), None
        )
        fuel_slot = next(
            (slot for slot in snapshot.slots if slot.group == "container_fuel"), None
        )
        output_slot = next(
            (slot for slot in snapshot.slots if slot.group == "container_output"), None
        )
        if input_slot is None or fuel_slot is None or output_slot is None:
            return {"ok": False, "error": "no_smelting_container"}

        actions: List[Dict[str, Any]] = []
        cursor_actions, cursor_error = self._clear_cursor_actions(snapshot)
        if cursor_error:
            return {"ok": False, "error": cursor_error}
        if cursor_actions:
            actions.extend(cursor_actions)

        available = self._build_counts(
            snapshot.slots, ("player_main", "player_hotbar")
        )
        total_available = available.get(input_item, 0)
        if total_available <= 0:
            return {"ok": False, "error": "missing_input", "item": input_item}
        if count <= 0:
            count = 1

        if input_slot.item and input_slot.item.name != input_item:
            return {
                "ok": False,
                "error": "input_slot_occupied",
                "item": input_item,
            }

        if output_slot.item:
            actions.append({"type": "quickMove", "slot": output_slot.slot})

        if fuel_slot.item is None:
            fuel_item = self._select_fuel_item(available)
            if fuel_item is None:
                return {"ok": False, "error": "missing_fuel"}
            fuel_source = next(
                (
                    slot
                    for slot in snapshot.slots
                    if slot.group in {"player_main", "player_hotbar"}
                    and slot.item is not None
                    and slot.item.name == fuel_item
                ),
                None,
            )
            if fuel_source is None:
                return {"ok": False, "error": "missing_fuel"}
            actions.append({"type": "quickMove", "slot": fuel_source.slot})

        remaining = count
        if input_slot.item and input_slot.item.name == input_item:
            remaining = max(0, remaining - input_slot.item.count)
        if remaining > 0:
            source_slots = [
                slot
                for slot in snapshot.slots
                if slot.group in {"player_main", "player_hotbar"}
                and slot.item is not None
                and slot.item.name == input_item
            ]
            for slot in source_slots:
                if remaining <= 0:
                    break
                actions.append({"type": "quickMove", "slot": slot.slot})
                remaining -= slot.item.count

        ok = await self._send_sequence(actions)
        if not ok:
            return {"ok": False, "error": "action_failed"}

        total_smelted = 0
        output_name = expected_output
        deadline = time.time() + timeout_sec
        while time.time() < deadline and total_smelted < count:
            await asyncio.sleep(0.5)
            raw = await self._get_snapshot(refresh=True)
            snapshot = ScreenSnapshot.from_dict(raw)
            if snapshot is None:
                break
            output_slot = next(
                (slot for slot in snapshot.slots if slot.group == "container_output"),
                None,
            )
            if output_slot and output_slot.item:
                output_name = output_slot.item.name
                total_smelted += output_slot.item.count
                await self._send_sequence(
                    [{"type": "quickMove", "slot": output_slot.slot}]
                )
                continue
            # 如果燃料用尽且输入还在，补充燃料
            fuel_slot = next(
                (slot for slot in snapshot.slots if slot.group == "container_fuel"),
                None,
            )
            input_slot = next(
                (slot for slot in snapshot.slots if slot.group == "container_input"),
                None,
            )
            if fuel_slot and (fuel_slot.item is None or fuel_slot.item.count <= 0):
                available = self._build_counts(
                    snapshot.slots, ("player_main", "player_hotbar")
                )
                fuel_item = self._select_fuel_item(available)
                if fuel_item:
                    fuel_source = next(
                        (
                            slot
                            for slot in snapshot.slots
                            if slot.group in {"player_main", "player_hotbar"}
                            and slot.item is not None
                            and slot.item.name == fuel_item
                        ),
                        None,
                    )
                    if fuel_source:
                        await self._send_sequence(
                            [{"type": "quickMove", "slot": fuel_source.slot}]
                        )
            input_slot = next(
                (slot for slot in snapshot.slots if slot.group == "container_input"),
                None,
            )
            if input_slot is None or input_slot.item is None:
                break

        return {
            "ok": total_smelted >= count,
            "input": input_item,
            "output": output_name,
            "smelted": total_smelted,
        }

    async def brew_item(self, params: Dict[str, Any]) -> Dict[str, Any]:
        item_name = _normalize_item_name(params.get("item"))
        count = int(params.get("count", 1))
        if not item_name:
            return {"ok": False, "error": "missing_item"}
        open_result = await self.open_brewing_stand({"radius": params.get("radius", 8), "move": True})
        if not open_result.get("ok"):
            return {"ok": False, "error": "brewing_stand_open_failed", "detail": open_result}
        goal = params.get("goal") or f"brew {item_name} x{count}"
        plan_params = {
            "goal": goal,
            "use_rag": params.get("use_rag", True),
            "use_mindcraft_docs": params.get("use_mindcraft_docs", True),
        }
        if params.get("rag_user_id"):
            plan_params["rag_user_id"] = params.get("rag_user_id")
        return await self.plan_actions(plan_params, execute=True)

    async def smith_item(self, params: Dict[str, Any]) -> Dict[str, Any]:
        item_name = _normalize_item_name(params.get("item"))
        count = int(params.get("count", 1))
        if not item_name:
            return {"ok": False, "error": "missing_item"}
        open_result = await self.open_smithing_table(
            {"radius": params.get("radius", 8), "move": True}
        )
        if not open_result.get("ok"):
            return {"ok": False, "error": "smithing_table_open_failed", "detail": open_result}
        goal = params.get("goal") or f"smith {item_name} x{count}"
        plan_params = {
            "goal": goal,
            "use_rag": params.get("use_rag", True),
            "use_mindcraft_docs": params.get("use_mindcraft_docs", True),
        }
        if params.get("rag_user_id"):
            plan_params["rag_user_id"] = params.get("rag_user_id")
        return await self.plan_actions(plan_params, execute=True)

    async def enchant_item(self, params: Dict[str, Any]) -> Dict[str, Any]:
        item_name = _normalize_item_name(params.get("item"))
        count = int(params.get("count", 1))
        if not item_name:
            return {"ok": False, "error": "missing_item"}
        open_result = await self.open_enchanting_table(
            {"radius": params.get("radius", 8), "move": True}
        )
        if not open_result.get("ok"):
            return {"ok": False, "error": "enchanting_table_open_failed", "detail": open_result}
        goal = params.get("goal") or f"enchant {item_name} x{count}"
        plan_params = {
            "goal": goal,
            "use_rag": params.get("use_rag", True),
            "use_mindcraft_docs": params.get("use_mindcraft_docs", True),
        }
        if params.get("rag_user_id"):
            plan_params["rag_user_id"] = params.get("rag_user_id")
        return await self.plan_actions(plan_params, execute=True)

    async def trade_item(self, params: Dict[str, Any]) -> Dict[str, Any]:
        item_name = _normalize_item_name(params.get("item"))
        count = int(params.get("count", 1))
        if not item_name:
            return {"ok": False, "error": "missing_item"}
        open_result = await self.open_trade({"radius": params.get("radius", 6), "move": True})
        if not open_result.get("ok"):
            return {"ok": False, "error": "trade_open_failed", "detail": open_result}
        goal = params.get("goal") or f"trade for {item_name} x{count}"
        plan_params = {
            "goal": goal,
            "use_rag": params.get("use_rag", True),
            "use_mindcraft_docs": params.get("use_mindcraft_docs", True),
        }
        if params.get("rag_user_id"):
            plan_params["rag_user_id"] = params.get("rag_user_id")
        return await self.plan_actions(plan_params, execute=True)

    async def smelt_item(self, params: Dict[str, Any]) -> Dict[str, Any]:
        input_item = _normalize_item_name(params.get("item"))
        count = int(params.get("count", 1))
        expected_output = _normalize_item_name(params.get("output"))
        timeout_sec = float(params.get("timeout_sec", 30.0))
        return await self._smelt_input(
            input_item,
            count,
            expected_output=expected_output or None,
            timeout_sec=timeout_sec,
        )

    async def _smelt_output_target(
        self, output_item: str, count: int, timeout_sec: float = 30.0
    ) -> Dict[str, Any]:
        raw = await self._get_snapshot(refresh=True)
        snapshot = ScreenSnapshot.from_dict(raw)
        if snapshot is None:
            return {"ok": False, "error": "no_snapshot"}
        available = self._build_counts(
            snapshot.slots, ("player_main", "player_hotbar")
        )
        input_item = self._select_smelt_input(output_item, available)
        if not input_item:
            return {"ok": False, "error": "no_smelt_recipe", "item": output_item}
        if available.get(input_item, 0) <= 0:
            return {"ok": False, "error": "missing_input", "item": input_item}
        if not (snapshot.screen_open and self._snapshot_has_smelting_container(snapshot)):
            auto_open = bool(
                self._headful_config().get("auto_open_furnace", True)
            )
            if auto_open:
                open_result = await self.open_furnace(
                    {
                        "radius": 8,
                        "move": True,
                    }
                )
                if not open_result.get("ok"):
                    return {
                        "ok": False,
                        "error": "open_furnace_failed",
                        "detail": open_result,
                    }
        return await self._smelt_input(
            input_item,
            count,
            expected_output=output_item,
            timeout_sec=timeout_sec,
        )

    async def _craft_item_once(self, params: Dict[str, Any], execute: bool = True) -> Dict[str, Any]:
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
            craft_output = self._infer_crafting_output(snapshot, grid)
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
                    if ok:
                        wait_timeout = min(12.0, max(1.0, len(actions) * 0.25 + 0.6))
                        await self._wait_for_queue_empty(len(actions), timeout=wait_timeout)
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
        all_recipes = recipe_book.get_recipes(item_name)
        if not all_recipes:
            return {"ok": False, "error": "no_recipe"}
        recipes = [r for r in all_recipes if self._recipe_fits(r, width, height)]
        if not recipes:
            if self._recipes_require_table(all_recipes):
                return {
                    "ok": False,
                    "error": "requires_crafting_table",
                    "item": item_name,
                    "grid": {"width": width, "height": height},
                }
            return {"ok": False, "error": "no_recipe"}

        available = self._build_counts(
            snapshot.slots,
            ("player_main", "player_hotbar"),
        )
        best = self._select_recipe(recipes, available)
        if best is None:
            return {"ok": False, "error": "no_recipe"}
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
            if ok:
                wait_timeout = min(12.0, max(1.0, len(actions) * 0.25 + 0.6))
                await self._wait_for_queue_empty(len(actions), timeout=wait_timeout)
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

    async def _craft_item_recursive(
        self,
        params: Dict[str, Any],
        depth: int = 0,
        chain: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        item_name = _normalize_item_name(params.get("item"))
        count = int(params.get("count", 1))
        if not item_name:
            return {"ok": False, "error": "missing_item"}
        max_depth = int(params.get("max_depth", 4))
        if depth > max_depth:
            return {"ok": False, "error": "craft_depth_exceeded", "item": item_name}
        if chain is None:
            chain = []
        if item_name in chain:
            return {"ok": False, "error": "craft_cycle_detected", "item": item_name}

        working_params = dict(params)
        substeps: List[Dict[str, Any]] = []
        max_rounds = int(working_params.get("max_rounds", 3))

        # 规划输出（资源图）
        try:
            allow_smelting = bool(working_params.get("allow_smelting", True))
            snap_plan_raw = await self._get_snapshot(refresh=True)
            snap_plan = ScreenSnapshot.from_dict(snap_plan_raw)
            available_counts: Dict[str, int] = {}
            if snap_plan is not None:
                available_counts = self._build_counts(
                    snap_plan.slots, ("player_main", "player_hotbar")
                )
            graph = self._get_resource_graph()
            plan_graph = graph.plan(
                item_name,
                count,
                available_counts,
                allow_smelting=allow_smelting,
                max_depth=max_depth,
            )
            self.last_plan = {"item": item_name, "count": count, "plan": plan_graph}
            if self._debug_enabled(working_params):
                try:
                    self._debug_log(
                        f"graph_plan {item_name}x{count} -> "
                        f"{json.dumps(plan_graph, ensure_ascii=False)[:900]}",
                        working_params,
                    )
                except Exception:
                    pass
        except Exception:
            self._logger.exception("graph_plan_failed")

        for round_idx in range(max_rounds + 1):
            result = await self._craft_item_once(working_params, execute=True)
            if result.get("ok"):
                if "steps" in result or "substeps" in result:
                    return result
                if substeps:
                    result["substeps"] = substeps
                elif chain:
                    result["substeps"] = []
                return result

            auto_open_table = bool(
                working_params.get(
                    "auto_open_table",
                    self._headful_config().get("auto_open_crafting_table", False),
                )
            )
            if result.get("error") == "requires_crafting_table" and auto_open_table:
                already_open = await self._wait_for_crafting_table(timeout=0.1)
                if already_open:
                    working_params["open_table_attempted"] = True
                    continue
                open_result = await self.open_crafting_table(
                    {
                        "radius": working_params.get(
                            "search_radius", working_params.get("radius", 8)
                        ),
                        "move": True,
                    }
                )
                if not open_result.get("ok"):
                    return {
                        "ok": False,
                        "error": "open_crafting_table_failed",
                        "detail": open_result,
                        "substeps": substeps,
                    }
                working_params["open_table_attempted"] = True
                continue

            if result.get("error") != "missing_items":
                if substeps:
                    result["substeps"] = substeps
                return result

            allow_smelting = bool(working_params.get("allow_smelting", True))
            if allow_smelting and self._is_smelt_output(item_name):
                smelt_result = await self._smelt_output_target(item_name, count)
                if substeps:
                    smelt_result["substeps"] = substeps
                elif chain:
                    smelt_result["substeps"] = []
                return smelt_result

            missing = result.get("missing") if isinstance(result, dict) else None
            if not isinstance(missing, dict) or not missing:
                if substeps:
                    result["substeps"] = substeps
                return result
            filtered_missing = {
                k: v for k, v in missing.items() if isinstance(v, int) and v > 0
            }
            if not filtered_missing:
                if substeps:
                    result["substeps"] = substeps
                return result
            self._debug_log(
                f"craft_recursive missing={filtered_missing} round={round_idx}",
                working_params,
            )

            base_missing = {
                k: v for k, v in filtered_missing.items() if self._is_base_item(k)
            }
            if base_missing:
                auto_gather = bool(
                    working_params.get(
                        "auto_gather_base_items",
                        self._headful_config().get("auto_gather_base_items", False),
                    )
                )
                if auto_gather and not working_params.get("auto_gather_attempted"):
                    working_params["auto_gather_attempted"] = True
                    gather_result = await self._auto_gather_missing_base_items(
                        base_missing, working_params
                    )
                    substeps.append(
                        {
                            "step": "auto_gather_base_items",
                            "missing": base_missing,
                            "result": gather_result,
                        }
                    )
                    if gather_result.get("ok"):
                        continue
                return {
                    "ok": False,
                    "error": "missing_base_items",
                    "item": item_name,
                    "missing": filtered_missing,
                    "substeps": substeps,
                }

            next_chain = list(chain)
            next_chain.append(item_name)
            for missing_item, missing_count in filtered_missing.items():
                sub_params = {
                    "item": missing_item,
                    "count": int(missing_count),
                    "max_times": working_params.get("max_times", 4),
                    "max_depth": max_depth,
                    "recursive": True,
                    "internal": True,
                    "allow_smelting": working_params.get("allow_smelting", True),
                }
                sub_result = await self._craft_item_recursive(
                    sub_params, depth=depth + 1, chain=next_chain
                )
                substeps.append(
                    {
                        "item": missing_item,
                        "count": int(missing_count),
                        "result": sub_result,
                    }
                )
                if not sub_result.get("ok"):
                    return {
                        "ok": False,
                        "error": "subcraft_failed",
                        "item": item_name,
                        "missing_item": missing_item,
                        "detail": sub_result,
                        "substeps": substeps,
                    }

        return {
            "ok": False,
            "error": "craft_retry_exhausted",
            "item": item_name,
            "substeps": substeps,
        }

    async def craft_item(self, params: Dict[str, Any], execute: bool = True) -> Dict[str, Any]:
        item_name = _normalize_item_name(params.get("item"))
        if not item_name:
            return {"ok": False, "error": "missing_item"}
        if not self._is_craft_allowed(item_name, params):
            return {"ok": False, "error": "craft_not_allowed", "item": item_name}
        if not execute:
            return await self._craft_item_once(params, execute=False)
        if not bool(params.get("recursive", True)):
            return await self._craft_item_once(params, execute=True)
        return await self._craft_item_recursive(params, depth=0, chain=None)
