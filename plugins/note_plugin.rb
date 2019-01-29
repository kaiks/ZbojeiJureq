class Note < Sequel::Model(:note)
  dataset_module do
    def from(nick)
      where(Sequel.lit(%(LOWER(nick) = "#{nick.downcase}")))
    end

    def for(nick)
      where(Sequel.lit(%(LOWER(nick_to) = "#{nick.downcase}")))
    end

    def due
      where(Sequel.lit("due <= datetime(CURRENT_TIMESTAMP, 'localtime') OR due IS NULL"))
    end
  end

  def to_s
    "#{posted.to_s[0..18]} <#{nick_from}> #{message}"
  end

  def to_s_for_sender
    "#{posted.to_s[0..18]} To #{nick_to}: #{message}"
  end

  def <=>(other)
    posted <=> other.posted
  end

  def due?
    Time.parse(time) <= Time.now
  end
end

class NotePlugin
  include Cinch::Plugin

  self.prefix = '.'

  NICK_REGEXP = /[0-9A-z_`\-\|\\\/\[\]]{1,16}/
  match /note (#{NICK_REGEXP}) (.+)/,    group: :note, method: :note
  match /noter (#{NICK_REGEXP}) (.+)/,    group: :note, method: :note
  match /note(\s[^\s].*)?/, group: :note, method: :help

  match /mynotes/,  group: :note, method: :show_notes
  match /timenote help/, group: :timenote, method: :timenote_help
  match /timenote ([0-9]{1,2}\.[0-9]{1,2}\.20[0-9]{2}) ([0-9]{1,2}:[0-9]{1,2}) (#{NICK_REGEXP}) (.+)/, group: :timenote, method: :timenote
  match /timenote ([0-9]{1,2}:[0-9]{1,2}) (#{NICK_REGEXP}) (.+)/, group: :timenote, method: :timenote_today


  match /.*/,  method: :notify, use_prefix: false

  def initialize(*args)
    super
  end

  def save_note(from:, to:, message:, due: nil)
    Note.create(posted: Time.now, nick_from: from, nick_to: to, message: message, due: due, status: 0)
  end

  def show_notes(m)
    user_notes = Note.where(status: 0).from(m.user.to_s).due.all.map(&:to_s_for_sender)
    if user_notes.empty?
      m.reply "You've got 0 unsent notes."
    else
      user_notes.each do |note|
        m.user.notice note
        sleep(3)
      end
    end
  end

  def note(m, recipient, message)
    save_note(from: m.user.to_s, to: recipient, message: message)
    m.user.notice 'Got it.'
  end

  def help(m)
    m.channel.send 'To post a note, type: .note [nick] [message]. To check your notes, type .mynotes'
  end

  def timenote_help(m)
    m.channel.send 'To post a time note, type: .timenote [date] [hour] [nick] [message]. (date is optional)'
  end

  def time_parse(hour, date = nil)
    if !date.nil?
      result = Time.parse("#{date} #{hour}") rescue nil
      raise 'Wrong date format. The correct format is dd.mm.YYYY HH:MM' if date.nil?
      return result
    end

    time = Time.parse(hour) rescue nil
    raise 'Wrong time format. The correct format is HH:MM' if time.nil?
    time > Time.now ? time : Time.parse("#{Date.today + 1} #{hour}")
  end

  def timenote(m, date, hour, recipient, message)
    begin
      time = time_parse(hour, date)
    rescue StandardError => e
      return m.reply(e.message)
    end

    save_note(from: m.user.to_s, to: recipient, message: text, due: time)
    m.user.send("Got it. Message will be delivered after #{time}", true)
  end

  def timenote_today(m, hour, recipient, message)
    begin
      time = time_parse(hour)
    rescue StandardError => e
      return m.reply(e.message)
    end

    save_note(from: m.user.to_s, to: recipient, message: message, due: time)
    m.user.send("Got it. Message will be delivered after #{time}", true)
  end

  def send_notes(m, notes)
    if notes.size > 1
      m.reply "You've got notes #{m.user.nick}!"
      delay = 1
      notes.each do |note|
        m.reply note
        sleep(delay)
        delay = [delay + 1, 5].min
      end
    else
      m.reply "#{m.user.nick}: #{notes.first}"
    end
  end

  def notify(m)
    user_notes = Note.where(status: 0)
                     .for(m.user.to_s)
                     .due
                     .order(:posted)
    return if user_notes.empty?

    send_notes(m, user_notes.all)
    user_notes.update(status: 1)
  end
end
