from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database import get_db
from models import Profile, User
from schemas import ProfileRead, ProfileWrite
from security import get_current_user
from sync import next_change_seq, not_found

router = APIRouter(
    prefix="/profile",
    tags=["Profile"],
)


@router.get("", response_model=ProfileRead)
def get_profile(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    profile = db.get(Profile, current_user.id)
    if profile is None:
        raise not_found("Profile")
    return profile


@router.put("", response_model=ProfileRead)
def put_profile(
    profile_data: ProfileWrite,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Creates the profile or replaces all of its fields."""
    profile = db.get(Profile, current_user.id)
    if profile is None:
        profile = Profile(user_id=current_user.id)
        db.add(profile)
    for field, value in profile_data.model_dump().items():
        setattr(profile, field, value)
    # Stored as JSON: strings, each once.
    profile.hidden_template_ids = list(dict.fromkeys(map(str, profile_data.hidden_template_ids)))
    profile.change_seq = next_change_seq(db, current_user)
    db.commit()
    db.refresh(profile)
    return profile
