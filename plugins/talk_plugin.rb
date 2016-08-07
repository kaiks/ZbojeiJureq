require './config.rb'

class TalkPlugin
  include Cinch::Plugin

  match /^[eE][zZ]$/,         method:  :ez, use_prefix:  false, ignore_case: true
  match /(.*)/,         method: :message, use_prefix: false

  timer CONFIG['talkdb_upload_delay'], method: :upload

  def initialize(*args)
    super
    @talkdb = Sequel.connect('jdbc:sqlite:talk.db')
    types = @talkdb[:types].select_hash(:description, :id)
  end

  def ez(m)
    m.reply 'eZ'
  end

#redo this shitty code
  def message(m, message)
    text = message.downcase.split
    trigger_reply = nil
    types = @talkdb[:types].select_hash(:description, :id)
    if text.length == 2
      #check CC, check CV, check VC
      var_trig ||= @talkdb[:variable_trigger].where(:full_string => message.downcase).first
      trigger_reply = @talkdb[:data].where(:var_trig_id => var_trig[:id]).order(Sequel.lit('RANDOM()')).limit(1) unless var_trig.nil?
      m.reply trigger_reply.first[:text] unless trigger_reply.nil?

    elsif text.length == 3
      #first check for 2 word triggers, then for 3 word triggers

      var_trig ||= @talkdb[:variable_trigger].where(:full_string => text[0]+' '+text[1]).first
      if !var_trig.nil?
        trigger_reply = @talkdb[:data].where(:var_trig_id => var_trig[:id]).order(Sequel.lit('RANDOM()')).limit(1) unless var_trig.nil?
        m.reply trigger_reply.first[:text] unless trigger_reply.first.nil?
        @talkdb[:data].insert(:text => message, :var_trig_id => var_trig[:id], :const_trig_id => var_trig[:constant_trigger_id], :nick => m.user.to_s)
      else
        #maybe it can be a variable trigger, just isn't one yet
        cv = @talkdb[:constant_trigger].where(:type => types['cv'], :string => text[0]).first
        #is it type cv?
        if !cv.nil?
          @talkdb[:variable_trigger].insert(:type => cv[:type], :constant_trigger_id => cv[:id], :string => text[1])
        else
          vc = @talkdb[:constant_trigger].where(:type => types['vc'], :string => text[1]).first
          #its not cv...is it type vc?
          if !vc.nil?
            @talkdb[:variable_trigger].insert(:type => vc[:type], :constant_trigger_id => vc[:id], :string => text[0])
          end
        end

        var_trig ||= @talkdb[:variable_trigger].where(:full_string => text[0]+' '+text[1]).first
        @talkdb[:data].insert(:text => message, :var_trig_id => var_trig[:id], :const_trig_id => var_trig[:constant_trigger_id], :nick => m.user.to_s) unless var_trig.nil?

        #finally, check for 3 word triggers
        if var_trig.nil?
          var_trig ||= @talkdb[:variable_trigger].where(:full_string => message.downcase).first
          trigger_reply = @talkdb[:data].where(:var_trig_id => var_trig[:id]).order(Sequel.lit('RANDOM()')).limit(1) unless var_trig.nil?
          m.reply trigger_reply.first[:text] unless trigger_reply.nil?
        end

      end

    elsif text.length > 3
      #for length >3:
      #cc
      #cv
      #vc
      #vvc

      #Check if the text is part of an already present 2 word trigger:
      var_trig ||= @talkdb[:variable_trigger].where(:full_string => text[0]+' '+text[1]).first
      if !var_trig.nil?
        trigger_reply = @talkdb[:data].where(:var_trig_id => var_trig[:id]).order(Sequel.lit('RANDOM()')).limit(1) unless var_trig.nil?
        m.reply trigger_reply.first[:text] unless trigger_reply.first.nil?
        @talkdb[:data].insert(:text => message, :var_trig_id => var_trig[:id], :const_trig_id => var_trig[:constant_trigger_id], :nick => m.user.to_s)
      else
        #maybe it can be a variable trigger cv or vc, just isn't one yet
        cv = @talkdb[:constant_trigger].where(:type => types['cv'], :string => text[0]).first
        #is it of type cv?
        if !cv.nil?
          @talkdb[:variable_trigger].insert(:type => cv[:type], :constant_trigger_id => cv[:id], :string => text[1])
        else
          vc = @talkdb[:constant_trigger].where(:type => types['vc'], :string => text[1]).first
          #its not cv...is it type vc?
          if !vc.nil?
            @talkdb[:variable_trigger].insert(:type => vc[:type], :constant_trigger_id => vc[:id], :string => text[0])
          end
        end


        var_trig ||= @talkdb[:variable_trigger].where(:full_string => text[0]+' '+text[1]).first
        #try to commit the 2 word string trigger and quit
        unless var_trig.nil?
          @talkdb[:data].insert(:text => message, :var_trig_id => var_trig[:id], :const_trig_id => var_trig[:constant_trigger_id], :nick => m.user.to_s)
          return
        end

        #It wasn't a part of a 2 word trigger. It might be a part of a 3 word trigger.
        var_trig ||= @talkdb[:variable_trigger].where(:full_string => text[0]+' '+text[1]+' '+text[2]).first
        #If it's an existing trigger, generate response and commit it
        if !var_trig.nil?
          trigger_reply = @talkdb[:data].where(:var_trig_id => var_trig[:id]).order(Sequel.lit('RANDOM()')).limit(1)
          m.reply trigger_reply.first[:text] unless trigger_reply.first.nil?
          @talkdb[:data].insert(:text => message, :var_trig_id => var_trig[:id], :const_trig_id => var_trig[:constant_trigger_id], :nick => m.user.to_s)
        else
          vvc = @talkdb[:constant_trigger].where(:type => types['vvc'], :string => text[2]).first
          unless vvc.nil?
            @talkdb[:variable_trigger].insert(:type => vvc[:type], :constant_trigger_id => vvc[:id], :string => text[0]+' '+text[1])
            var_trig ||= @talkdb[:variable_trigger].where(:full_string => text[0]+' '+text[1]+' '+text[2]).first
            @talkdb[:data].insert(:text => message, :var_trig_id => var_trig[:id], :const_trig_id => var_trig[:constant_trigger_id], :nick => m.user.to_s)
          end
        end
      end

    end
  end

  def upload
    @bot.upload_to_dropbox './talk.db'
  end


end