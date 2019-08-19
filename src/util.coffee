# utilities to be used by commands
# gotta keep things tidy.

emojme = require 'emojme'
fs = require 'graceful-fs'

module.exports = (robot) ->
  emojme_download: (request, original_request, subdomain, token, action) ->
    request.send("Updating emoji database, this may take a few moments...")
    downloadPromise = if process.env.LOCAL_EMOJI
      new Promise (resolve) ->
        resolve {subdomain: {emojiList: JSON.parse(fs.readFileSync(process.env.LOCAL_EMOJI, 'utf-8'))}}
    else
      emojme.download(subdomain, token, {})

    downloadPromise
      .then (adminList) =>
        lastUser = request.message.user.name
        lastUpdate = Date(Date.now()).toString()
        emojiList = adminList[Object.keys(adminList)[0]].emojiList
        robot.brain.set 'emojme.AuthUser', lastUser
        robot.brain.set 'emojme.LastUpdatedAt', lastUpdate
        robot.brain.set 'emojme.AdminList', emojiList

        original_request.send("#{request.message.user.name} updated the emoji cache, make sure to thank them!")
        action(emojiList, lastUser, lastUpdate)
      .catch (e) ->
        console.log("[ERROR] #{e}")
        request.send("Looks like something went wrong, is your token correct?")

  do_login: (request, original_request, action) ->
    dialog = robot.emojmeConversation.startDialog request, 60000
    dm = request.envelope.user.id
    robot.send {room: dm}, "Hey #{request.envelope.user.name}, in order to refresh the emoji cache I'm gonna need a [user token](https://github.com/jackellenberger/emojme#finding-a-slack-token), just plop that below like ```token: xoxs-...```"
    robot.send {room: dm}, "You've got 60 seconds. No pressure."

    dialog.addChoice /(?:token: )?(.*:)?(xoxs-.*)/i, (tokenResponse) ->
      subdomain = (tokenResponse.match[1] || request.message.user.slack.team_id).replace(/:/g,'').trim()
      token = tokenResponse.match[2].trim()
      action(subdomain, token)
      robot.send {room: dm}, "Thanks! Carrying on..."

  require_cache: (request, action) ->
    if (
      (emojiList = robot.brain.get 'emojme.AdminList' ) &&
      (lastUser = robot.brain.get 'emojme.AuthUser' ) &&
      (lastRefresh = robot.brain.get 'emojme.LastUpdatedAt' )
    )
      action emojiList, lastUser, lastRefresh
    else
      request.send "The emoji cache has gone missing, would you mind updating it? I've sent you few instructions."
      self = this # Guh
      self.do_login request, request, (subdomain, token) ->
        self.emojme_download request, request, subdomain, token, (emojiList, lastUser, lastUpdate) ->
          action(emojiList, lastUser, lastUpdate)

  find_emoji: (request, emojiList, emojiName, action) ->
    if typeof emojiName != 'undefined' && (emoji = emojiList.find((emoji) -> emoji.name == emojiName))
      original_name = emoji.alias_for
      if original_name && (original_emoji = emojiList.find((emoji) -> emoji.name == original_name))
        action(emoji, original_emoji)
      else
        action(emoji)
    else
      request.send("I don't recognize :#{emojiName}:, if it exists, my cache might need a refresh. Call `emojme refresh` to find out how")

  find_author: (request, emojiList, authorName, action) ->
    this.find_emoji_by 'user_display_name', authorName, emojiList, (authorsEmoji) ->
      if authorsEmoji && authorsEmoji.length > 0
        action(authorsEmoji)
      else
        this.find_display_name_by_name authorName, (realAuthorName) ->
          if realAuthorName
            this.find_emoji_by 'user_display_name', realAuthorName, emojiList, (authorsEmoji) ->
              if authorsEmoji && authorsEmoji.length > 0
                action(authorsEmoji)
              else
                request.send("Hmm, '#{authorName}', a.k.a '#{realAuthorName}', huh? Never heard of em. Either they don't exist or they have no emoji.")
          else
            request.send("Hmm, '#{authorName}', huh? Never heard of em. Either they don't exist, they have no emoji, or you're not using their Slack display name.")

  find_emoji_by: (field, value, emojiList, action) ->
    action(emojiList.filter((emoji) -> emoji[field] == value))

  find_display_name_by_name: (name, action) ->
    user = robot.brain.userForName(name.replace(/@/g,''))
    if user
      action(user.real_name)

  find_archive_entry: (emoji_name, action) ->
    emoji_archive = robot.brain.get "emojme.emojiArchive"
    emoji_archive ?= {}
    action(emoji_archive[emoji_name])

  save_archive_entry: (emoji_name, message, action) ->
    emoji_archive = robot.brain.get "emojme.emojiArchive"
    emoji_archive ?= {}
    emoji_archive[emoji_name] = message
    robot.brain.set "emojme.emojiArchive", emoji_archive

  delete_archive_entry: (emoji_name) ->
    emoji_archive = robot.brain.get "emojme.emojiArchive"
    emoji_archive ?= {}
    delete emoji_archive[emoji_name]
    robot.brain.set "emojme.emojiArchive", emoji_archive
