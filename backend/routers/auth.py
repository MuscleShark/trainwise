from fastapi import APIRouter, Depends

from models import User
from schemas import UserRead
from security import get_current_user

# Sign-up and sign-in happen in Clerk. The API only identifies the signed-in user.
router = APIRouter(
    tags=["Authentication"],
)


@router.get("/me", response_model=UserRead)
def me(
    current_user: User = Depends(get_current_user),
):
    return current_user
