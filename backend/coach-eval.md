| Model | Passed | Cost per suggestion | Median time |
|---|---|---|---|
| anthropic:claude-opus-5-5 | 22/24 (92%) | $0.0134 | 3.6 s |
| anthropic:claude-sonnet-5-5 | 23/24 (96%) | $0.0068 | 2.8 s |
| anthropic:claude-haiku-5-5 | 21/24 (88%) | $0.0005 | 3.1 s |

### Failures: anthropic:claude-opus-5-5

- a little less sleep than usual (en): number not in the input: 40
- a little less sleep than usual (zh): number not in the input: 40

### Failures: anthropic:claude-sonnet-5-5

- rules already held for sleep (zh): number not in the input: 2.5

### Failures: anthropic:claude-haiku-5-5

- increase after a short night (en): number not in the input: 15
- rules already held for sleep (zh): number not in the input: 2.5
- a little less sleep than usual (zh): number not in the input: 40
