# Character animations

Mixamo clips used by every imported character (see `scripts/game/character_animations.gd`).
They were exported for the Nikol character "without skin" at 30 fps; any Mixamo-rigged
character can use them because the bone names match.

| File | Used for |
|---|---|
| idle.fbx / idle_fight.fbx | standing still, calm / in a fight |
| walk.fbx / run.fbx | moving (exported in place) |
| cross.fbx, jab.fbx, hook.fbx | punch combo 1, 2, 3 |
| kick.fbx | kick |
| throw.fbx | throwing whatever you carry |
| getup_back.fbx / getup_front.fbx | getting up after a knockdown |
| lift.fbx | downloaded, not used yet |

To swap a motion, download another Mixamo clip (FBX, without skin) and save it under the
same name. Delete a file to fall back to the built-in code animation for that motion.
