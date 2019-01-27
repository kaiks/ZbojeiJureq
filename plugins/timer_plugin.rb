#timer status:
# 0 - waiting
# 1 - completed

require 'set'
require 'time'


class TimerNoteTest < Sequel::Model(:timer)

  def time
    inserted
  end

  def due?
    Time.parse(time) <= Time.now
  end

  def to_s
    "[#{time.to_s[0..18]}] <#{nick}> #{message}"
  end

  def <=>(note)
    Time.parse(time) <=> Time.parse(note.time)
  end

  def self.sorted
    self.where(:status => 0).all.sort!
  end

  def self.due
    self.where(:status => 0).where{ trigger_time <= Time.now }
  end

  def self.pending
    self.where{ trigger_time >= Time.now }
  end

end

class TimerPlugin

  include Cinch::Plugin
  self.prefix = '.'
  match /timer show/,                                                group: :timer_command, method: :show_timers
  match /timer ([0-9]+\.?[0-9]*)\s?(d|h|m|s) (.+)/,                  group: :timer_command, method: :timer_note
  match /timer ([0-9]{1,2}:[0-9]{1,2}) (.+)/,                        group: :timer_command, method: :timer_hour
  match /timer ([0-9]{1,2}\.[0-9]{1,2}\.20[0-9]{2}) ([0-9]{1,2}:[0-9]{1,2}) (.+)/, group: :timer_command, method: :timer_date
  match /timer(.*)/,                                                 group: :timer_command, method: :timer_help



  #debug
  match /print_notes/, method: :print_notes

  timer 5, method: :timed

  def initialize(*args)
    super
    puts "-------------------Got #{TimerNoteTest.count} notes ----------------"
  end

  def print_notes(m)
    TimerNoteTest.due.all.each { |n| puts n.to_s; puts n.inspect }
  end

  def show_timers(m)
    TimerNoteTest.pending.where(:nick => m.user.nick).limit(3).each { |n| @bot.User(m.user.nick).notice "Due #{n.trigger_time}: #{n}" }
  end

  def timed
    due_notes = TimerNoteTest.due

    while due_notes.count > 0
      note = due_notes.first
      @bot.Channel(note[:channel]).send note.to_s
      note.update(:status => 1)
    end

  end


  def timer_note(m, amount, scale, text)
    amount = amount.to_i

    case scale
      when 'd'
        amount *= 3600*24
      when 'h'
        amount *= 3600
      when 'm'
        amount *= 60
    end


    TimerNoteTest.create(:trigger_time => Time.now+amount,
                         :nick => m.user.nick, :channel => m.channel.to_s,
                         :message => text, :inserted => Time.now,
                         :status => 0
    )

    m.user.msg("Got it. Message will be sent #{Time.now+amount}",true)

  end


  def timer_hour(m, amount, text)
    time = amount.split(':')
    hours = time[0].to_i
    minutes = time[1].to_i



    today = Date.today.to_s

    date = Time.parse("#{today} #{amount}") rescue nil
    if (date.nil?)
      m.user.send('Wrong time format. The correct format is HH:MM')
      return
    end

    date = Time.parse("#{(Date.today+1).to_s} #{amount}") if date < Time.now

    TimerNoteTest.create(:trigger_time => date,
                         :nick => m.user.nick, :channel => m.channel.to_s,
                         :message => text, :inserted => Time.now,
                         :status => 0
    )

    m.user.send("Got it. Message will be sent at #{date}",true)

  end


  def timer_date(m, date, hour, text)

    date = Time.parse("#{date} #{hour}") rescue nil

    if date.nil? || date < Time.now
      m.user.msg('Wrong date format. The correct format is dd.mm.YYYY HH:MM')
      return
    end

    TimerNoteTest.create(:trigger_time => date,
                         :nick => m.user.nick, :channel => m.channel.to_s,
                         :message => text, :inserted => Time.now,
                         :status => 0
    )

    m.user.msg("Got it. Message will be sent on #{date}",true)

  end

  def timer_help(m, arg)
    m.channel.send 'example: .timer 5 m test - to get the timer manual, go to http://kaiks.eu/help/timer.html'
  end

end