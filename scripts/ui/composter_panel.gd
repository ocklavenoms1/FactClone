extends ProcessorPanel

## Composter UI (session-soil-exhaustion-3). Crops → Compost.
## Standard input → progress → output layout from ProcessorPanel.
## No overrides needed — slot_layout in Buildings.DATA[COMPOSTER] drives
## rendering, and Composter selects the active recipe at runtime
## (multi-recipe like Smelter; ProcessorPanel just shows whatever recipe
## is currently set in b.state["recipe_id"]).
##
## 12th ProcessorPanel consumer (joins Mill, Oven, Proofer, Packager,
## Loom, Tailor, Briquetter, Sugar Press, Retter, Yeast Culture, Thresher).
