-- Manual data fixes that are not captured by generated diffs.
do
  -- Quest 41682 needs gossip objective item 2020173.
  pfDB["quests"]["data-turtle"][41682]["obj"]["O"] = { 2020173 }

  -- Item 41783 is dropped by NPC 62217.
  pfDB["items"]["data-turtle"][41783]["U"] = { [62217] = 1.0 }
end
