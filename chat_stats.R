load("data/dowis.RData")

#### STAT FUNCTIONS ####

add_message_features <- function(data) {
  data %>%
    mutate(
      date = as.Date(datetime),
      year = year(datetime),
      month = floor_date(datetime, "month"),
      week = floor_date(datetime, "week", week_start = 1),
      weekday = wday(datetime, label = TRUE, week_start = 1),
      hour = hour(datetime),
      n_chars = str_length(body),
      n_words = str_count(body, "\\S+"),
      has_url = str_detect(body, "https?://"),
      has_question = str_detect(body, "\\?"),
      has_emoji = str_detect(body, "[\\p{So}\\p{Sk}]")
    )
}

stats_by_sender <- function(data) {
  data %>%
    add_message_features() %>%
    group_by(sender_name) %>%
    summarise(
      n_messages = n(),
      first_message = min(datetime, na.rm = TRUE),
      last_message = max(datetime, na.rm = TRUE),
      total_words = sum(n_words, na.rm = TRUE),
      total_chars = sum(n_chars, na.rm = TRUE),
      avg_words_per_message = mean(n_words, na.rm = TRUE),
      median_words_per_message = median(n_words, na.rm = TRUE),
      avg_chars_per_message = mean(n_chars, na.rm = TRUE),
      n_questions = sum(has_question, na.rm = TRUE),
      n_urls = sum(has_url, na.rm = TRUE),
      n_emoji_messages = sum(has_emoji, na.rm = TRUE),
      pct_questions = n_questions / n_messages,
      pct_urls = n_urls / n_messages,
      pct_emoji_messages = n_emoji_messages / n_messages,
      .groups = "drop"
    ) %>%
    arrange(desc(n_messages))
}

messages_over_time <- function(data, period = "month") {
  data %>%
    mutate(period = floor_date(datetime, period)) %>% 
    count(period, sender_name, name = "n_messages") %>% 
    arrange(period, sender_name)
}

activity_by_hour <- function(data) {
  data %>%
    add_message_features()  %>% 
    count(sender_name, hour, name = "n_messages") %>%
    arrange(sender_name, hour)
}

activity_by_weekday <- function(data) {
  data %>%
    add_message_features() %>%
    count(sender_name, weekday, name = "n_messages") %>%
    arrange(sender_name, weekday)
}

message_gaps <- function(data) {
  data %>%
    arrange(datetime) %>%
    mutate(
      previous_sender = lag(sender_name),
      previous_datetime = lag(datetime),
      gap_minutes = as.numeric(difftime(datetime, previous_datetime, units = "mins")),
      sender_changed = sender_name != previous_sender
    )
}


conversation_starters <- function(data, silence_hours = 12) {
  data %>%
    arrange(datetime) %>%
    mutate(
      previous_datetime = lag(datetime),
      gap_hours = as.numeric(difftime(datetime, previous_datetime, units = "hours")),
      starts_new_conversation = is.na(gap_hours) | gap_hours >= silence_hours
    ) %>%
    filter(starts_new_conversation) %>%
    count(sender_name, name = "n_conversation_starts") %>%
    arrange(desc(n_conversation_starts))
}

chat_summary <- function(data) {
  list(
    sender_stats = stats_by_sender(data),
    weekly_messages = messages_over_time(data, "week"),
    weekday_activity = activity_by_weekday(data),
    hourly_activity = activity_by_hour(data),
    conversation_starters_12h = conversation_starters(data, 12),
    conversation_starters_24h = conversation_starters(data, 24),
    message_gaps = message_gaps(data)
  )
}
#### EXAMPLE USAGE ####
summary_dowis <- chat_summary(dowis)
dowi_stats <- summary_dowis$sender_stats
print(dowi_stats)

save(summary_dowis, file="data/summary_dowis.RData")