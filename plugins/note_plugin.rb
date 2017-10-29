class Note < Sequel::Model(:note)

  def to_s
    "#{posted.to_s[0..18]} <#{nick_from}> #{message}"
  end

  def to_s_for_sender
    "#{posted.to_s[0..18]} To #{nick_to}: #{message}"
  end

  def <=>(note)
    posted <=> note.posted
  end

end

class NotePlugin
  include Cinch::Plugin

  self.prefix = '.'


  match /note ([0-9A-z_`\-\|\\\/\[\]]{1,16}) (.+)/,    group: :note, method: :note
  match /noter ([0-9A-z_`\-\|\\\/\[\]]{1,16}) (.+)/,    group: :note, method: :note
  match /note(\s[^\s].*)?/, group: :note, method: :help

  match /mynotes/,group: :note, method: :show_notes


  match /.*/,  method: :notify, use_prefix: false

  def initialize(*args)
    super
  end

  def show_notes(m)
    user_notes = []
    Note.where(:nick_from => m.user.to_s, :status => 0).all.each { |note|
      user_notes << note.to_s_for_sender
    }
    if user_notes.size == 0
      m.reply 'You\'ve got 0 unsent notes.'
    else
      user_notes.each{|note|
        m.user.notice note
      }
    end
  end

  def note(m, recipient, message)
    Note.create(:posted => Time.now, :nick_from => m.user.to_s, :nick_to => recipient, :message => message, :status => 0)
    m.user.notice 'Got it.'
  end

  def help(m)
    m.channel.msg 'To post a note, type: .note [nick] [message]. To check your notes, type .mynotes'
  end

  def notify(m)
    user_notes = []
    Note.where(:nick_to => m.user.to_s, :status => 0).order(:posted).all.each { |note|
      user_notes << note.to_s
      note.update(:status => 1)
    }
    if user_notes.size > 1
      m.reply "You've got notes #{m.user.nick}!"
      user_notes.each { |note|
        m.reply note
      }
    elsif
      user_notes.size == 1
      m.reply "#{m.user.nick}: #{user_notes[0]}"
    end
  end


end