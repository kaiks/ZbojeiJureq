UNODB = sqlite_load('uno.db')

class UnoGameModel < Sequel::Model(UNODB[:games])
  def time_start
    Time.parse(start)
  end
end

class UnoTurnModel < Sequel::Model(UNODB[:turn])
end

# 0 - join
# 1 - remove
# 2 - stop
class UnoActionModel < Sequel::Model(UNODB[:player_action])
end

class UnoRankModel < Sequel::Model(UNODB[:uno])
  unrestrict_primary_key
end
