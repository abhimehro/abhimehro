# Optional static README cards (not enabled)

Hosted endpoint in use: `https://github-stats-extended.vercel.app`

Enable this path only if the hosted endpoint becomes unreliable.

## Verified action pins (as of 2026-08-04)

| Action                                          | Latest verified                            | Notes                                                              |
| :---------------------------------------------- | :----------------------------------------- | :----------------------------------------------------------------- |
| `stats-organization/github-readme-stats-action` | **v2.0.2** (also moving tags `v2`, `v2.0`) | Prefer immutable `v2.0.2` or commit SHA                            |
| `actions/checkout`                              | **v7.0.1** (major v7)                      | Existing health workflow still on v4; bump when touching workflows |

Do **not** copy unreviewed major bumps from blog posts. Re-check:

```bash
gh api repos/stats-organization/github-readme-stats-action/tags --jq '.[].name' | head
gh api repos/actions/checkout/releases/latest --jq .tag_name
```

## Draft workflow (disabled)

Save as `grs-static-cards.yml` only when needed. Uses verified pins:

```yaml
name: Update README cards

on:
  schedule:
    - cron: "17 12 * * *"
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v7.0.1

      - name: Generate stats card
        uses: stats-organization/github-readme-stats-action@v2.0.2
        with:
          card: stats
          options: >-
            username=${{ github.repository_owner }}&show_icons=true&include_all_commits=true&hide_border=true&border_radius=12&title_color=7DD3FC&icon_color=2DD4BF&text_color=CBD5E1&bg_color=0B1C2C&ring_color=38BDF8&rank_icon=percentile
          path: profile/stats.svg
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Generate top-langs card
        uses: stats-organization/github-readme-stats-action@v2.0.2
        with:
          card: top-langs
          options: >-
            username=${{ github.repository_owner }}&layout=compact&langs_count=8&card_width=320&hide_border=true&border_radius=12&title_color=7DD3FC&text_color=CBD5E1&bg_color=0B1C2C&size_weight=0.5&count_weight=0.5
          path: profile/top-langs.svg
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Commit cards
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          mkdir -p profile
          git add profile/*.svg
          git commit -m "Update README cards" || exit 0
          git push
```

Then embed `./profile/stats.svg` instead of the hosted URLs.
