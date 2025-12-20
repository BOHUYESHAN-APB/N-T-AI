import enum
from typing import List, Dict, Optional, Any
from pydantic import BaseModel, Field

class PlanStepStatus(str, enum.Enum):
    NOT_STARTED = "not_started"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"
    BLOCKED = "blocked"

class PlanStep(BaseModel):
    id: str
    title: str
    description: str = ""
    status: PlanStepStatus = PlanStepStatus.NOT_STARTED
    dependencies: List[str] = []
    result: Optional[str] = None
    metadata: Dict[str, Any] = {}

class FlowManager:
    """
    Manages the execution flow of a Deep Research task.
    Inspired by OpenManus PlanningFlow.
    """
    def __init__(self, steps: List[Dict[str, Any]]):
        self.steps: List[PlanStep] = []
        self._init_steps(steps)
        self.current_step_index = 0

    def _init_steps(self, raw_steps: List[str]):
        """Initialize steps from a list of strings."""
        for i, step_text in enumerate(raw_steps):
            # Create a simplified step object
            # In a real DAG, we would parse dependencies.
            # Here we assume sequential for now, but structure it for future DAG support.
            self.steps.append(PlanStep(
                id=f"step_{i+1}",
                title=step_text,
                status=PlanStepStatus.NOT_STARTED
            ))

    def get_next_step(self) -> Optional[PlanStep]:
        """Returns the next NOT_STARTED step."""
        for step in self.steps:
            if step.status == PlanStepStatus.NOT_STARTED:
                return step
        return None

    def mark_step_start(self, step_id: str):
        for step in self.steps:
            if step.id == step_id:
                step.status = PlanStepStatus.IN_PROGRESS
                break

    def mark_step_complete(self, step_id: str, result: str = ""):
        for step in self.steps:
            if step.id == step_id:
                step.status = PlanStepStatus.COMPLETED
                step.result = result
                break
    
    def mark_step_failed(self, step_id: str, error: str = ""):
        for step in self.steps:
            if step.id == step_id:
                step.status = PlanStepStatus.FAILED
                step.result = error
                break

    def get_plan_snapshot(self) -> List[Dict[str, Any]]:
        """Returns a serializable snapshot of the current plan."""
        return [step.model_dump() for step in self.steps]
