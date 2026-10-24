import json
import uuid
import os

file_path = 'Packages/TorrlyCore/Sources/TorrlyCore/Resources/default-providers.json'

mirrors = [
    {
        "name": "kattracker",
        "url_template": "https://kattracker.com/usearch/%s/?field=size&sorder=desc",
        "type": "html",
        "rows": "table > tbody > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(3)\" }",
        "leechers": "{ qs: \"td:eq(4)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "247prox",
        "url_template": "https://247prox.com/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(2)\" }",
        "leechers": "{ qs: \"td:eq(3)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "tpb.vip",
        "url_template": "https://tpb.vip/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(3)\" }",
        "leechers": "{ qs: \"td:eq(4)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "tpb.world",
        "url_template": "https://tpb.world/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(3)\" }",
        "leechers": "{ qs: \"td:eq(4)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "pirateproxy.dev",
        "url_template": "https://pirateproxy.dev/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(3)\" }",
        "leechers": "{ qs: \"td:eq(4)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "1337x.unblockit.link",
        "url_template": "https://1337x.unblockit.link/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(3)\" }",
        "leechers": "{ qs: \"td:eq(4)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "zooqle",
        "url_template": "https://zooqle.com/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(2)\" }",
        "leechers": "{ qs: \"td:eq(3)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "idope",
        "url_template": "https://idope.com/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(2)\" }",
        "leechers": "{ qs: \"td:eq(3)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "torlock",
        "url_template": "https://torlock.com/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(2)\" }",
        "leechers": "{ qs: \"td:eq(3)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "limetorrents.lol",
        "url_template": "https://limetorrents.lol/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(2)\" }",
        "leechers": "{ qs: \"td:eq(3)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "torrentz2/torrentz2k",
        "url_template": "https://torrentz2.com/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(2)\" }",
        "leechers": "{ qs: \"td:eq(3)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "bitsearch",
        "url_template": "https://bitsearch.com/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(2)\" }",
        "leechers": "{ qs: \"td:eq(3)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "torrentdownload.info",
        "url_template": "https://torrentdownload.info/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(2)\" }",
        "leechers": "{ qs: \"td:eq(3)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "the punycode limetorrents",
        "url_template": "https://limetorrents.com/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(2)\" }",
        "leechers": "{ qs: \"td:eq(3)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    },
    {
        "name": "thepibay",
        "url_template": "https://thepibay.com/search?q={query}",
        "type": "html",
        "rows": "table > tr",
        "name": "{ qs: \"td:eq(0)\" }",
        "size": "{ qs: \"td:eq(1)\" }",
        "seeds": "{ qs: \"td:eq(2)\" }",
        "leechers": "{ qs: \"td:eq(3)\" }",
        "magnet": "{ qs: \"td:eq(0) a\", access: \"href\" }"
    }
]

with open(file_path, 'r') as f:
    data = json.load(f)

new_entries = []
for m in mirrors:
    # Replace %s in url_template with {query} for consistency
    url = m["url_template"].replace("%s", "{query}")
    new_entries.append({
        "id": str(uuid.uuid4()),
        "name": m["name"],
        "isEnabled": False,
        "html": {
            "request": {
                "url": {
                    "default": url
                }
            },
            "rows": m["rows"],
            "name": m["name"],
            "size": m["size"],
            "seeds": m["seeds"],
            "leechers": m["leechers"],
            "magnet": m["magnet"]
        }
    })

data.extend(new_entries)

with open(file_path, 'w') as f:
    json.dump(data, f, indent=2)
