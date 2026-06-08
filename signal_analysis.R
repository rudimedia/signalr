setwd("/Users/breitner/local_research/signalr")

filepath <- "data/signal-export-2026-06-08-07-24-41/main.jsonl"
pacman::p_load(jsonlite, tidyverse, lubridate, stringr)
chats <- jsonlite::stream_in(file(filepath))

#### whats in it? ####
dateReceived <- chats$chatItem$incoming$dateReceived
dateReceived[!is.na(dateReceived)]

# givenNames and familyNames are the system given / family names for recipients 
givenNames <- chats$recipient$contact$systemGivenName
givenNames[!is.na(givenNames)]

familyNames <- chats$recipient$contact$systemFamilyName
familyNames[!is.na(familyNames)]

# chatId identifies the chat in which a message was sent
chatId <- chats$chatItem$chatId
chatId[!is.na(chatId)]

# authorId identifies who sent a message 
authorId <- chats$chatItem$authorId
authorId[!is.na(authorId)]

# bodies are the texts sent / received
bodies <- chats$chatItem$standardMessage$text$body
bodies[!is.na(bodies)]

# recipientId_pk is the primary key to which authorId (probably) points
recipientId_pk <- chats$recipient$id

# chatId_pk is the primary key to which chatId (probably points)
chatId_pk <- chats$chat$id

#### build tables ####

recipients <- tibble(
  recipient_id = chats$recipient$id,
  given_name   = chats$recipient$contact$systemGivenName,
  family_name  = chats$recipient$contact$systemFamilyName
) %>%
  filter(!is.na(recipient_id)) %>% 
  mutate(
    sender_name = str_squish(str_c(given_name, family_name, sep = " ")),
    sender_name = na_if(sender_name, ""),
    sender_name = coalesce(sender_name, recipient_id)
  ) %>% 
  distinct(recipient_id, .keep_all = TRUE)

messages <- tibble(
  chat_id       = chats$chatItem$chatId,
  author_id     = chats$chatItem$authorId,
  date_received = chats$chatItem$incoming$dateReceived,
  date_sent     = chats$chatItem$dateSent,
  body          = chats$chatItem$standardMessage$text$body
) %>%
  filter(!is.na(body)) %>%
  mutate(
    message_date = coalesce(date_received, date_sent),
    message_date = as.numeric(message_date),
    datetime = as.POSIXct(
      message_date / 1000,
      origin = "1970-01-01",
      tz = "Europe/Berlin"
    )
  )

messages_with_senders <- messages %>%
  left_join(
    recipients,
    by = c("author_id" = "recipient_id")
  ) %>%
  select(
    datetime,
    chat_id,
    author_id,
    sender_name,
    body
  )

messages_with_senders$sender_name <- ifelse(messages_with_senders$sender_name == "725", "Sam Känner", messages_with_senders$sender_name)

# adjust the ID!
dowis <- messages_with_senders[messages_with_senders$chat_id == "713", ]


#### Analysis ####

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

messages_over_time(pepe, "week") %>% 
  ggplot(aes(x = period, y = n_messages, color = sender_name)) +
  geom_line() +
  geom_point() +
  labs(
    x = NULL,
    y = "Messages",
    color = "Sender"
  )

activity_by_hour <- function(data) {
  data %>%
    add_message_features()  %>% 
    count(sender_name, hour, name = "n_messages") %>%
    arrange(sender_name, hour)
}
activity_by_hour(pepe)

activity_by_hour(pepe) %>%
  ggplot(aes(x = hour, y = n_messages, color = sender_name)) +
  geom_line() +
  geom_point() +
  scale_x_continuous(breaks = 0:23) +
  labs(
    x = "Hour of day",
    y = "Messages",
    color = "Sender"
  )

activity_by_weekday <- function(data) {
  data %>%
    add_message_features() %>%
    count(sender_name, weekday, name = "n_messages") %>%
    arrange(sender_name, weekday)
}

activity_by_weekday(pepe) %>%
  ggplot(aes(x = weekday, y = n_messages, fill = sender_name)) +
  geom_col(position = "dodge") +
  labs(
    x = NULL,
    y = "Messages",
    fill = "Sender"
  )

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

message_gaps(pepe) %>%
  filter(!is.na(gap_minutes), gap_minutes < 60 * 24 * 2) %>%
  group_by(sender_name) %>%
  summarise(
    avg_gap_minutes = mean(gap_minutes, na.rm = TRUE),
    median_gap_minutes = median(gap_minutes, na.rm = TRUE),
    .groups = "drop"
  )

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

#### DoWis ####

summary_dowis <- chat_summary(dowis)
dowi_stats <- summary_dowis$sender_stats

pacman::p_load(patchwork)

plot_sender_bar <- function(data, y, ylab, title) {
  ggplot(data, aes(x = sender_name, y = .data[[y]], fill = sender_name)) +
    geom_col(show.legend = FALSE) +
    labs(
      x = "DoWi",
      y = ylab,
      title = title
    ) +
    theme_minimal(base_size = 11) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      plot.title = element_text(face = "bold")
    )
}

p1 <- plot_sender_bar(
  dowi_stats,
  "avg_words_per_message",
  "Average words per message",
  "Average words"
)

p2 <- plot_sender_bar(
  dowi_stats,
  "median_words_per_message",
  "Median words per message",
  "Median words"
)

p3 <- plot_sender_bar(
  dowi_stats,
  "n_questions",
  "# Questions",
  "Questions"
)

p4 <- plot_sender_bar(
  dowi_stats,
  "n_urls",
  "# URLs",
  "URLs"
)

p5 <- plot_sender_bar(
  dowi_stats,
  "n_emoji_messages",
  "# Emoji messages",
  "Emoji messages"
)

pdf("dowi_stats.pdf", width=10, height=10)
(
  (p1 | p2) /
    (p3 | p4) /
    (p5 | patchwork::plot_spacer())
) +
  plot_annotation(
    title = "DoWi chat statistics"
  )
dev.off()
