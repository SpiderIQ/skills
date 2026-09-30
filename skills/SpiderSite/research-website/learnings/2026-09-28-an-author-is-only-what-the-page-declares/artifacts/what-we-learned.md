# An author is only what the page declares

`sources[].author` and `sources[].published_at` are never guessed. They come from what the page
says about itself, in this order:

1. structured data — a JSON-LD `Article` / `BlogPosting` / `NewsArticle` author and date
2. meta tags — `author`, `article:published_time` and the like
3. a byline that links to the site's author page (`/author/<name>/`)
4. a `<time>` element
5. for a PDF, the document's own metadata

`null` means none of those is there. It does not mean the page has no author.

## What the first live run showed

The post `https://blog.cloudflare.com/announcing-1111/` declares its date in structured data but
names its author only as a byline link to an author page.

| Run | `author` | Why |
|---|---|---|
| 1 | `null` | author-page links were not read at all |
| 2 | `Matthew Prince, Michelle Zatlyn, Jules Lemee` | every author link on the page was read — including the bylines of the related posts at the foot of the page |
| 3 | `Matthew Prince` | only the first byline's own container is read |

The date was `2018-04-01T13:01:00.000Z` in all three runs.

## What to do with it

- Report `author` and `published_at` as the page's own claim, and `null` as "the page does not say".
- Never fill them from the article text or from the site's name.
- Several comma-separated names are what the byline credits — report them as given.
