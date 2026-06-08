setwd("/Users/breitner/local_research/signalr")

filepath <- "data/signal-export-2026-06-08-07-24-41/main.jsonl"
pacman::p_load(jsonlite, tidyverse, lubridate, stringr)
chats <- jsonlite::stream_in(file(filepath))

#### TABLES ####

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

#### EXTRACT CHATS (TO-DO) ####
#' Extract individual chats from the data
#' Currently requires figuring out your sender_name which is numeric
#' ==> that's not hard to do, just View() or print() messages_with_senders, sender_name is what you are searching for.
#' ==> In my case, the first entries are from "note to self" so all are sent by me. don't know if that's always the case.
#' Also requires knowing the chat_id, cannot yet filter by chat / group name

# 1. Replace your Sender ID with your Name
name <- "Sam Känner"
your_id <- "725"
messages_with_senders$sender_name <- ifelse(messages_with_senders$sender_name == your_id, name, messages_with_senders$sender_name)

save(messages_with_senders, file="data/messages_with_senders.RData")

# 2. Filter out the chat you want to analyse
chat_id <- "713"
dowis <- messages_with_senders[messages_with_senders$chat_id == chat_id, ]

save(dowis, file="data/dowis.RData")
