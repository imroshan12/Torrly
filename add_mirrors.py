import json
import uuid
import os

file_path = 'Packages/TorrlyCore/Sources/TorrlyCore/Resources/default-providers.json'

if not os.path.exists(file_path):
    print(f"Error: {file_path} not found.")
    exit(1)

mirrors = [
    "kattracker",
    "247prox",
    "tpb.vip",
    "tpb.world",
    "pirateproxy.dev",
    "1337x.unblockit.link",
    "zooqle",
    "idope",
    "torlock",
    "limetorrents.lol",
    "torrentz2/torrentz2k",
    "bitsearch",
    "torrentdownload.info",
    "the punycode limetorrents",
    "thepibay"
]

with open(file_path, 'r') as f:
    data = json.load(f)

new_entries = []
for mirror in mirrors:
    # Use a slightly better dummy json structure
    new_entries.append({
        "id": str(uuid.uuid4()),
        "name": mirror,
        "isEnabled": False,
        "json": {
            "url": {
                "default": "https://{mirror}/search?q={query}"
            },
            "resultsPath": "",
            "name": "name",
            "size": "size",
            "seeds": "seeders",
            "leechers": "leechers",
            "infoHash": "info_hash",
            "category": "category",
            "typeValidation": {}
        }
    })

data.extend(new_entries)

with open(file_path, 'w') as f:
    json.dump(data, f, indent=2)

print("Successfully added mirrors.")
