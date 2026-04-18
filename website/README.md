# SoccerCoach Website

This is the static marketing website for the `SoccerCoach` iPhone app.

## Files
- `index.html` - homepage
- `privacy.html` - privacy policy page for App Store submission
- `styles.css` - shared site styling
- `.nojekyll` - tells GitHub Pages to serve the site as plain static files

## GitHub Pages Setup
This folder is already wired for GitHub Pages with the workflow at:
- `.github/workflows/deploy-pages.yml`

If you make the `SoccerCoach` folder its own GitHub repository, you can publish the site like this:

1. Create a new GitHub repository.
2. Push the contents of the `SoccerCoach` folder to the `main` branch of that repository.
3. In GitHub, open `Settings` > `Pages`.
4. Under `Build and deployment`, choose `GitHub Actions` as the source.
5. Push to `main` again if needed, or run the `Deploy SoccerCoach Website` workflow manually.

Your site will be published at a URL like:
- `https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPOSITORY_NAME/`

The privacy policy page will be:
- `https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPOSITORY_NAME/privacy.html`

## Before Publishing
1. Replace the support contact placeholder in `privacy.html`.
2. If you want, add your App Store link to `index.html` once the listing is live.
3. Use the final public URLs in App Store Connect for your marketing URL and privacy policy URL.
