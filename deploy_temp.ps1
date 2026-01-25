Set-Location build\web
git init
git add .
git commit -m "Deploy to GitHub Pages"
git branch -M main
git remote add origin https://github.com/Chhrid17/myTodo-app.git
git push -u -f origin main:gh-pages
