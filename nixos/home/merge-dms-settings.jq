. as $current
| $overlay[0] as $managed
| . * $managed
| .barConfigs = (
    [$managed.barConfigs[] | . as $bar
      | ([$current.barConfigs[]? | select(.id == $bar.id)][0] // {}) as $local
      | $local * $bar
      | if ($local | has("screenPreferences")) then .screenPreferences = $local.screenPreferences else . end
    ]
    + [$current.barConfigs[]? | select(.id as $id | ($managed.barConfigs | map(.id) | index($id)) == null)]
  )
