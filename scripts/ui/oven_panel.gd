extends ProcessorPanel

## Oven UI (session-building-ui-2). Risen Dough + Fuel Briquette → Bread.
## Two solid input slots stacked vertically (dough above, fuel below) per
## ProcessorPanel default layout. Both inputs share in_buffer (multi-type
## bag). No overrides needed.
##
## Note: oven uses fuel-as-recipe-input (not Burner). Briquette is just
## another input slot — see PROJECT_LOG session-building-ui-2 decisions
## for why we didn't convert oven to Burner this session.
