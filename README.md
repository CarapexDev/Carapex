# Carapex

This repository is a static site. Netlify should publish the repository root with no build step.

## Local preview

Run a simple static server from the repo root:

```sh
python3 -m http.server 3000
```

Then open `http://localhost:3000`.

## Branch preview workflow

Use a feature branch for changes instead of working on `main`:

```sh
git switch -c codex/your-change
git push -u origin codex/your-change
```

For Netlify:

1. Connect the GitHub repository to a Netlify site.
2. Leave the production branch on `main`.
3. Enable Deploy Previews for pull requests.
4. Enable Branch deploys for the branches you want preview URLs for, such as `codex/dev`.

With the `netlify.toml` in this repo, production, deploy previews, and branch deploys all publish the static site from the repository root.
