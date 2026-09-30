# Understanding Lake

View the presentation with `presenterm slides.md`
(requires [presenterm](https://github.com/mfontanini/presenterm))

Alternatively generate the PDF of the slides with Pandoc:

```sh
pandoc slides.md -t beamer \
  --pdf-engine=lualatex \
  -V theme=default \
  -V monofont="DejaVu Sans Mono" \
  -o slides.pdf
```
