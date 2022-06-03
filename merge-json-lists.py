#!/usr/bin/env python3
# Use this script to join JSON lists stored in files.
# Usage:
# python3 merge-json-lists.py json-list-1.json json-list-2.json ... > merged-lists.json

import json
import sys


def merge_lists(*file_list):
    final_list = []
    for filepath in file_list:
        with open(filepath, "rt", encoding="UTF-8") as file:
            json_list = json.load(file)
        final_list += json_list
    json.dump(final_list, sys.stdout)


def main():
    file_list = sys.argv[1:]
    merge_lists(*file_list) 


if __name__ == "__main__":
    main()
