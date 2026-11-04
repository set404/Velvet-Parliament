# Playable characters

Drop character models here (`.fbx`, `.glb`, `.gltf` or `.blend`). Each one shows up on
the character select screen before the session starts, named after its file:
`davit_kirakosyan.fbx` becomes "Davit Kirakosyan". Sub-folders are fine, so a model can
keep its textures next to it:

    characters/
      davitik/davitik.fbx
      davitik/davitik_diffuse.png
      ani.fbx

What works best:

- A humanoid model rigged with a skeleton. Mixamo rigs work as-is (upload to
  mixamo.com, auto-rig, download as FBX with no animation). Unreal, Blender Rigify/DEF
  and Godot humanoid bone names are recognised too.
- Any pose (T-pose, A-pose), any size, any facing direction. The game stands the model
  up, scales it to about 1.8 m and turns it to face forward.
- Animations inside the file aren't needed; the game animates the skeleton itself
  (walking, punches, kicks, carrying, ragdoll knockdowns).

A model without a skeleton still works, but moves stiffly as one piece. If a rigged
model shows up stiff, its bone names weren't recognised: the Output panel prints a
warning, and the names can be added to `BONES` in `scripts/game/character_skin.gd`.
