# Pet creation contract for coding agents

When a user attaches photos or videos of one pet and asks for a desktop pet, treat the media as the source of truth and complete the workflow without requiring the user to understand sprite sheets or manifests.

1. Infer the pet name, species, likely breed, body proportions, coat/markings, eyes, ears, tail and permanent accessories from the attachments. If breed is uncertain, record `breed: null`; do not invent certainty. Ask only when multiple pets are present and the target cannot be inferred.
2. Never substitute a generic animal for the referenced individual. Record stable visual traits in `profile.identity_features` and unusual proportions in `profile.body_traits`.
3. Initialize the pack with `python3 Tools/petpack.py init`. Supported first-class species are `cat`, `dog`, `rabbit` and `ferret`; use `other` for another animal and derive its safe signature action from the videos.
4. Generate or prepare transparent PNG poses and frame sequences listed in `generation-plan.md`. Preserve the same identity, canvas, scale, baseline and accessory geometry in every frame.
5. Derive motion from the animal, not from the default cat. Rabbits hop with hind-limb propulsion; dogs use a canine quadruped gait; ferrets keep a low, flexible trunk; cats use alternating quadruped contacts. Prefer the user's video cadence when available.
6. Generate at least three valid sleep shapes for the animal. Inspect every frame for duplicated or missing ears, forelimbs, hind limbs and tails.
7. Build a contact sheet and animated previews. Reject foot sliding, frozen leading limbs, identity drift, abrupt size/baseline changes, missing transition frames, detached toy movement and non-looping loop endpoints.
8. Run `python3 Tools/petpack.py validate <pack> --strict`. Do not call the pack complete while strict validation has errors.
9. The finished pack must run unchanged in both `DockCatApp` (macOS) and `WindowsPet` (Windows). Do not place source photos or videos in Git; `.petpack-local.json` is local-only.

If image generation is unavailable, still scaffold the pack and report the exact missing animation rows. Do not fabricate a successful QA result.
