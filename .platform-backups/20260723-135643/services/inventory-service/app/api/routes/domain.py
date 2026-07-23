from threading import Lock
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

router = APIRouter(prefix="/inventory", tags=["inventory"])
_lock = Lock()
_items: dict[UUID, "InventoryItem"] = {}


class InventoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    category: str = Field(min_length=1, max_length=100)
    quantity: int = Field(ge=0)
    location: str = Field(min_length=1, max_length=255)


class InventoryItem(InventoryCreate):
    id: UUID


@router.get("", response_model=list[InventoryItem])
def list_inventory() -> list[InventoryItem]:
    return list(_items.values())


@router.post("", response_model=InventoryItem, status_code=status.HTTP_201_CREATED)
def create_inventory(payload: InventoryCreate) -> InventoryItem:
    item = InventoryItem(id=uuid4(), **payload.model_dump())
    with _lock:
        _items[item.id] = item
    return item


@router.get("/{item_id}", response_model=InventoryItem)
def get_inventory(item_id: UUID) -> InventoryItem:
    item = _items.get(item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Inventory item not found")
    return item


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_inventory(item_id: UUID) -> None:
    with _lock:
        if _items.pop(item_id, None) is None:
            raise HTTPException(status_code=404, detail="Inventory item not found")

