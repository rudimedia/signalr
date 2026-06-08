dowis <- messages_with_senders[messages_with_senders$chat_id == "713", ]
summary_dowis <- chat_summary(dowis)
dowi_stats <- summary_dowis$sender_stats

pacman::p_load(tinyplot)

View(dowis[dowis$datetime >= as.POSIXct("2026-03-18", tz = "Europe/Berlin") & dowis$datetime < as.POSIXct("2026-03-20", tz = "Europe/Berlin"),])
