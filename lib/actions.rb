class Being
  attr_reader :name, :health

  # shielded blocks physical damage
  # resistance is for elements
  # haste is number of hasted turns remaining
  # time_stop is whether time will stop for this being at the end of the turn
  # time_stopped is whether time is currently stopped for this being
  # paralyzed_by records who paralyzed this being
  attr_accessor :shielded, :resistance, :haste, :time_stop, :time_stopped, :amnesia
  attr_reader :paralyzed_by

  def initialize
    @shielded = false
    @resistance = {}
    @haste = 0
    @protection = 0
  end

  def remove_enchantments
    # TODO
  end

  def tick
    @shielded = @protection > 0
    @protection = [0, @protection - 1].max
    @haste = [0, @haste - 1].max
    @paralyzed_by = nil
    @amnesiac = @amnesia
    @amnesia = false
  end

  def paralyze user
    @paralyzed_by = user
  end

  def paralyzed_this_turn
    @paralyzed_by != nil
  end

  def physical_damage x, attacker
    if @shielded && (!attacker.time_stopped || @time_stopped)
      return false
    end
    @health -= x
    true
  end

  def elemental_damage x, element, attacker
    if @resistance[element] && (!attacker.time_stopped || @time_stopped)
      return false
    end
    @health -= x
    true
  end

  def magical_damage x
    @health = @health -= x
  end

  def heal x
    @health += x
  end

  def protection= p
    if p > 0
      @shielded = true
      @protection = p
    else
      @protection = 0
    end
  end

  def clamp_health
    @health = [0, [@health, @max_health].min].max
  end

  def kill
    @health = 0
  end

  def revive
    prev = @health
    @health = @max_health
    prev
  end

  def haste?
    @haste > 0
  end

  def to_s
    "#{@name} (#{[0, [@health, @max_health].min].max}/#{@max_health})"
  end
end

# player character
class Warlock < Being
  attr_reader :up, :down, :select
  attr_accessor :index, :choices, :targets, :paralyzed_hand, :charm_target, :current_beings, :paralysis_target

  GESTURES = [:f, :p, :s, :w, :d, :c, :>, :-]

  def initialize name, up, down, select
    super()
    @name = name
    @up = up
    @down = down
    @select = select

    @max_health = 15
    @health = @max_health
    @index = 0
    # left, right
    @gestures = [[], []] # all
    @new_gestures = []
    @choices = []
    @targets = []

    @did_paralyze = false
    @paralyzed_hand = nil
  end

  def tick
    super
    @paralyzed_hand = nil
  end

  def finalize_input
    @gestures[0] << @new_gestures[0]
    @gestures[1] << @new_gestures[1]
    @did_paralyze = false
    @new_gestures = []
    @choices = []
    @targets = []
  end

  def last_gesture hand
    last = -1
    loop do
      gesture = @gestures[hand][last]
      return gesture unless gesture == :antispell
      last -= 1
    end
  end

  # paralysis/amnesia/charm could change gestures
  def update_gestures args
    if @paralyzed_hand
      gesture = last_gesture @paralyzed_hand
      paralyzed_gesture =
        case gesture
        when :c
          :f
        when :s
          :d
        when :w
          :p
        else
          gesture
        end
      args.state.result << "#{self.name} #{%w{left right}[@paralyzed_hand]} hand paralyzed: #{paralyzed_gesture}"
      @new_gestures[@paralyzed_hand] = paralyzed_gesture
    elsif @amnesiac
      [0, 1].each do |hand|
        @new_gestures[hand] = last_gesture hand
      end
    end
  end

  # because of paralysis/charm, gestures may not match choices. randomly correct that now
  def update_choices
    # TODO: implement real spell system
  end

  def menu_state
    # TODO: charm
    # TODO: monster target if you control (or any spell _could_ control) a monster
    if @paralysis_target && (!@did_paralyze || @targets.length >= 2)
      :paralysis
    elsif @new_gestures.length == 0 || @targets.length >= 2
      :left_gesture
    elsif @choices.length == 0
      :left_choice
    elsif @targets.length == 0
      :left_target
    elsif @new_gestures.length == 1
      :right_gesture
    elsif @choices.length == 1
      :right_choice
    elsif @targets.length == 1
      :right_target
    else
      raise "logic error in determining current menu state: #{inspect}"
    end
  end

  def menu
    case menu_state
    when :paralysis
      # TODO: show target's previous hand gestures
      %w{left right}
    when :left_gesture, :right_gesture
      # TODO: previews of what each gesture accomplishes
      GESTURES.map(&:to_s)
    when :left_choice, :right_choice
      # TODO: real spell selection system
      Actions.map(&:name)
    when :left_target, :right_target
      @current_beings.map(&:name)
    else
      raise "unhandled menu state: #{menu_state}"
    end
  end

  def menu_down
    @index = (@index + 1) % menu.length
  end

  def menu_up
    @index = (@index - 1) % menu.length
  end

  def reset_index
    case menu_state
    when :paralysis
      @index = 0
    when :left_gesture, :right_gesture
      @index = 0
    when :left_choice, :right_choice
      @index = 0
    when :left_target, :right_target
      if (@choices[@targets.length - 1].default_target || :self) == :self
        @index = @current_beings.index { |b| b == self }
      else
        @index = @current_beings.index { |b| b.is_a?(Warlock) && b != self }
      end
    else
      raise "unhandled menu state: #{menu_state}"
    end
  end

  def menu_select
    case menu_state
    when :paralysis
      @paralysis_target.paralyzed_hand = @index
      @did_paralyze = true
      # clear all other inputs in case they are redoing them
      @new_gestures = []
      @choices = []
      @targets = []
    when :left_gesture, :right_gesture
      # if redoing input, clear previous
      if @new_gestures.length >= 2
        @new_gestures = []
      end
      @new_gestures << GESTURES[index]
      if @new_gestures.length == 1
        # clear all other inputs in case they are redoing them (and didn't paralyze/charm)
        @choices = []
        @targets = []
      end
      case @new_gestures[-1]
      when :c
        @new_gestures = [:c, :c]
      when :>
        if @new_gestures.length >= 2 && @new_gestures[0] == :>
          @new_gestures = [:-, :>]
        end
      end
    when :left_choice, :right_choice
      @choices << Actions[@index]
    when :left_target, :right_target
      @targets << @current_beings[@index]
    else
      raise "unhandled menu state: #{menu_state}"
    end
    reset_index
  end

  def ready_to_resolve
    @targets.length >= 2
  end
end

# anything that can automatically attack
class Monster < Being
end

# goblins, trolls, etc.
class Minion < Monster
  def self.count
    @i ||= 0
    @i += 1
  end

  attr_accessor :controller, :target

  def initialize strength, species
    super()
    @max_health = strength
    @attack = strength
    @health = @max_health
    # TODO: cooler name
    @name = "#{species} #{self.class.count}"
  end

  def attack
    Attack.new self, @target, @attack
  end
end

# cannot be controlled, attacks indiscriminately
class Elemental < Monster
  attr_reader :element

  def initialize strength, element
    super()
    @max_health = strength
    @attack = strength
    @health = @max_health
    @element = element
    @resistance = {@element => true}
    # TODO: cooler name
    @name = "#{element}"
  end

  def attack
    ElementalAttack.new self, @attack, @element
  end
end

class Action
  class << self
    attr_reader :name, :default_target, :order
  end

  attr_reader :origin
  attr_accessor :user, :target

  def initialize user, target
    @origin = user
    @user = user
    # only actions with a default target can be targeted
    if self.class.default_target
      @target = target
    end
  end

  def name
    self.class.name
  end

  def <=> other
    self.class.order <=> other.class.order
  end

  def description
    "#{@user.name}: #{name} #{@target ? @target.name : nil}"
  end

  def resolve args
    args.state.result << "#{name} does nothing"
  end
end

class DispelMonsters < Action
  def initialize
    # nothing to do
  end

  def resolve args
    args.state.beings.reject! do |being|
      if being.is_a? Monster
        args.state.result << "Dispelled: #{being.name}"
        true
      end
    end
  end
end

# TODO: general pass to make sure actions don't affect dead beings in weird ways

class Spell < Action
  class << self
    attr_reader :type
  end

  def description
    subject =
      if self.class.default_target == :self && @target == @user
        ""
      elsif @target == @user
        " on himself"
      elsif @target == nil
        ""
      else
        " on #{@target.name}"
      end
    "#{@user.name} casts #{name}#{subject}"
  end
end

class SummonSpell < Spell
  class << self
    attr_reader :strength
  end

  def self.type
    :summoning
  end

  def self.name
    "Summon #{@name}"
  end

  def self.monster_name
    @name
  end
end

class Attack < Action
  @default_target = :other

  def initialize user, target, str
    super user, target
    @strength = str
  end

  def description
    "#{@user.name} attacks #{@target.name} (#{@strength})"
  end

  def resolve args
    if @user.paralyzed_this_turn
      args.state.result << "#{@user.name} is paralyzed!"
      return
    elsif @user.amnesia
      args.state.result << "#{@user.name} forgets to attack!"
      return
    end
    if target.physical_damage @strength, @user
      args.state.result << description
    else
      args.state.result << "#{description} (shielded)"
    end
  end
end

class ElementalAttack < Action
  def initialize user, str, element
    super user, nil
    @strength = str
    @element = element
  end

  def resolve args
    if @user.paralyzed_this_turn
      args.state.result << "#{@user.name} is paralyzed!"
      return
    elsif @user.amnesia
      args.state.result << "#{@user.name} forgets to attack!"
      return
    end
    # attack all non-resistant beings
    args.state.beings.each do |being|
      next if being == @user || being.health <= 0 # other than itself or a dead being
      if being.elemental_damage @strength, @element, @user
        args.state.result << "#{@user.name} attacks #{being.name} (#{@strength})"
      else
        args.state.result << "#{@user.name} attacks #{being.name} (#{@strength}) (resisted)"
      end
    end
  end
end

class SummonMinion < SummonSpell
  def resolve args
    controller =
      case @target
      when Minion
        @target.controller
      when Elemental
        args.state.result << "#{description} (invalid target)"
        return
      when Warlock
        @target
      end

    # create a minion
    minion = Minion.new self.class.strength, self.class.monster_name
    minion.controller = controller

    # TODO: should prompt warlock for minion target on turn it is summoned
    if controller == args.state.west
      minion.target = args.state.east
    else
      minion.target = args.state.west
    end

    args.state.beings << minion

    # minions immediately attack
    args.state.actions << minion.attack
  end
end

class SummonElemental < SummonSpell
  class << self
    attr_reader :element
  end

  def resolve args
    existing = {fire: [], ice: []}
    existing[:fire].concat args.state.beings.select { |b| b.is_a?(Elemental) && b.element == :fire }
    existing[:ice ].concat args.state.beings.select { |b| b.is_a?(Elemental) && b.element == :ice  }

    alive = existing.transform_values { |es| es.select { |b| b.health > 0 } }

    summon = {fire: [], ice: []}
    summon[self.class.element] << self

    storms = {fire: [], ice: []}

    args.state.actions.each do |action|
      if action.is_a? SummonElemental
        summon[action.class.element] << action
      elsif action.is_a? StormSpell
        storms[action.class.element] << action
      end
    end

    total = {}
    [:fire, :ice].each do |e|
      total[e] = alive[e].length + summon[e].length + storms[e].length
    end

    # at most one storm or elemental can exist per turn
    # if the elements mix, everything cancels
    if total[:fire] > 0 && total[:ice] > 0
      # kill all elementals
      args.state.beings.each do |b|
        next unless b.is_a? Elemental
        b.kill
        # remove their attacks before they take effect
        args.state.actions.reject! { |a| a.user == b }
      end
      # cancel all summons and storms
      cancelled = [self]
      args.state.actions.reject! do |action|
        if action.is_a?(SummonElemental) || action.is_a?(StormSpell)
          cancelled << action
          true
        end
      end
      # if any ice storms happened, also cancel fireballs
      if cancelled.any? { |a| a.is_a?(IceStorm) }
        args.state.actions.reject! do |action|
          if action.is_a? Fireball
            cancelled << action
            true
          end
        end
      end
      cancelled.each do |spell|
        args.state.result << "Cancelled: #{spell.description}"
      end
    else # only one element is present, so _something_ will happen
      element = total[:fire] > 0 ? :fire : :ice

      if storms[element].empty? # can summon
        # remove all redundant summons
        args.state.actions.reject! { |a| a.is_a? SummonElemental }
        summon[element].each do |spell|
          args.state.result << spell.description
        end

        # heal existing elemental or summon new one
        if existing[element].first
          if existing[element].first.revive == 0
            # immediately attack if it was dead
            args.state.actions << existing[element].first.attack
          end
        else
          elemental = Elemental.new(self.class.strength, element)
          args.state.beings << elemental
          existing[element] << elemental
          # new elementals immediately attack
          args.state.actions << elemental.attack
        end
      else # storm takes precedence
        # kill all elementals
        args.state.beings.each do |b|
          next unless b.is_a? Elemental
          b.kill
          # remove their attacks before they take efffect
          args.state.actions.reject! { |a| a.user == b }
        end
        # cancel all summons (storms will resolve later)
        cancelled = [self]
        args.state.actions.reject! do |action|
          if action.is_a?(SummonElemental)
            cancelled << action
            true
          end
        end
        cancelled.each do |spell|
          args.state.result << "Cancelled: #{spell.description}"
        end
      end
    end
  end
end

class DispelMagic < Spell
  @name = 'Dispel Magic'
  @default_target = :self
  @order = 0
  @type = :protection

  def resolve args
    # stop all spells (resolve all other dispel magics)
    shielded = [@user]
    args.state.result << description

    args.state.actions.reject! do |action|
      if action.is_a? DispelMagic
        shielded << action.user
        args.state.result << action.description
      elsif action.is_a? Spell
        args.state.result << "Cancelled: #{action.description}"
      end
      action.is_a? Spell
    end

    # remove all enchantments from all beings
    args.state.beings.each do |being|
      being.remove_enchantments
    end

    # destroy all monsters (after they attack)
    args.state.actions << DispelMonsters.new

    # shield anyone who cast Dispel Magic
    shielded.each do |being|
      being.shielded = true
    end
  end
end

class CounterSpell < Spell
  @name = 'Counter Spell'
  @default_target = :self
  @order = 1
  @type = :protection

  def resolve args
    # cancel all spells cast at the target (except Finger of Death)
    cancelled = []
    args.state.actions.reject! do |action|
      if action.is_a?(Spell) && action.target == @target && !action.is_a?(FingerOfDeath)
        cancelled << action
        true
      end
    end

    @target.shielded = true

    args.state.result << description
    cancelled.each do |spell|
      args.state.result << "Cancelled: #{spell.description}"
    end
  end
end

class MagicMirror < Spell
  @name = 'Magic Mirror'
  @default_target = :self
  @order = 2
  @type = :protection

  def resolve args
    mirrored = {@target => true}

    # resolve all mirrors
    args.state.actions.reject! do |action|
      if action.is_a?(MagicMirror)
        mirrored[action.target] = true
        true
      end
    end

    args.state.result << description

    # reflect all spells against mirrored targets
    args.state.actions.each do |action|
      next unless action.is_a?(Spell)
      while mirrored[action.target] && action.target != action.origin
        args.state.result << "Reflected: #{action.description}"
        action.user, action.target = action.target, action.user
      end
    end
  end
end

class SummonGoblin < SummonMinion
  @name = 'Goblin'
  @default_target = :self
  @order = 3
  @strength = 1
end
class SummonOgre < SummonMinion
  @name = 'Ogre'
  @default_target = :self
  @order = 4
  @strength = 2
end
class SummonTroll < SummonMinion
  @name = 'Troll'
  @default_target = :self
  @order = 5
  @strength = 3
end
class SummonGiant < SummonMinion
  @name = 'Giant'
  @default_target = :self
  @order = 6
  @strength = 4
end

class SummonFireElemental < SummonElemental
  @name = 'Fire Elemental'
  @order = 7
  @strength = 3
  @element = :fire
end
class SummonIceElemental < SummonElemental
  @name = 'Ice Elemental'
  @order = 8
  @strength = 3
  @element = :ice
end

class RaiseDead < Spell
  @name = 'Raise Dead'
  @default_target = :self
  @order = 9
  @type = :protection

  def resolve args
    # cancel Fingers of Death
    filtered = args.state.actions.reject! do |action|
      if action.is_a? FingerOfDeath
        args.state.result << "Cancelled: #{action.description}"
        true
      end
    end

    # if cancelled, also cancel all Raise Deads (including this one)
    if filtered
      args.state.result << "Cancelled: #{description}"
      args.state.actions.reject! do |action|
        if action.is_a? RaiseDead
          args.state.result << "Cancelled: #{action.description}"
          true
        end
      end
      return
    end

    # if the target can actually be raised
    if @target.health <= 0
      # resolve all Raise Deads
      raises = [self]
      args.state.actions.reject! do |action|
        if action.is_a? RaiseDead
          raises << action
          true
        end
      end

      users = raises.map do |r|
        args.state.result << r.description
        r.user
      end.uniq

      if @target.is_a?(Minion)
        if users.length == 1
          # TODO: should prompt warlock for minion target on turn it is raised
          @target.controller = users[0]
          @target.target = args.state.beings.find { |b| b.is_a?(Warlock) && b != users[0] }
        else # minion is confused
          # TODO confused monsters attack at random
          @target.controller = nil
          @target.target = nil
        end
      end

      @target.revive
      if @target.is_a? Monster
        args.state.actions << @target.attack
      end
      return
    end

    args.state.result << "#{description} (5)"
    @target.heal 5
  end
end

class Haste < Spell
  @name = 'Haste'
  @default_target = :self
  @order = 10
  @type = :enchantment

  def resolve args
    args.state.result << description
    @target.haste = 3
  end
end

class TimeStop < Spell
  @name = 'Time Stop'
  @default_target = :self
  @order = 11
  @type = :enchantment

  def resolve args
    args.state.result << description
    @target.time_stop = true
  end
end

class Protection < Spell
  @name = 'Protection'
  @default_target = :self
  @order = 12
  @type = :enchantment

  def resolve args
    args.state.result << description
    @target.protection = 3
  end
end

class ResistanceSpell < Spell
  class << self
    attr_reader :element
  end

  def resolve args
    if @target.is_a?(Elemental)
      if @target.element == self.class.element && @target.health > 0
        args.state.result << description
        args.state.result << "Destroyed: #{@target.name}"
        @target.kill
        args.state.actions.reject! { |a| a.user == @target }
      else
        args.state.result << "#{description} with no effect"
      end
    else
      args.state.result << description
      @target.resistance[self.class.element] = true
    end
  end
end

class ResistHeat < ResistanceSpell
  @name = 'Resist Heat'
  @default_target = :self
  @order = 13
  @type = :enchantment
  @element = :fire
end
class ResistCold < ResistanceSpell
  @name = 'Resist Cold'
  @default_target = :self
  @order = 14
  @type = :enchantment
  @element = :ice
end

class Paralysis < Spell
  @name = 'Paralysis'
  @default_target = :other
  @order = 15
  @type = :enchantment

  def resolve args
    cancelled = []
    # paralyses cancel each other
    args.state.actions.reject! do |action|
      if action.is_a?(Paralysis) && action.target == @target
        cancelled << action
        true
      end
    end

    # if other paralyses happened, or any other charm, cancel this spell
    if cancelled.length > 0 || args.state.actions.any? { |a| a.target == @target && [Amnesia, Confusion, CharmPerson, CharmMonster, Fear].any? { |t| a.is_a? t } }
      cancelled.unshift self
    end

    if cancelled.length > 0
      cancelled.each do |action|
        args.state.result << "Cancelled: #{action.description}"
      end
      return
    end

    args.state.result << description
    @target.paralyze @user

    # slightly hacky: if a non-warlock paralyzes a non-paralyzed warlock, randomly choose the paralyzed hand now
    # this lets us show the paralyzed hand now and the system to maintain paralysis will do the rest
    if !@user.is_a?(Warlock) && @target.is_a?(Warlock) && !@target.paralyzed_hand
      @target.paralyzed_hand = rand(2)
      args.state.result << "#{@user.name} paralyzes #{@target.name}'s #{%w{left right}[@target.paralyzed_hand]} hand"
    end
  end
end

class Amnesia < Spell
  @name = 'Amnesia'
  @default_target = :other
  @order = 16
  @type = :enchantment

  def resolve args
    cancelled = []
    args.state.actions.reject! do |action|
      if action.target == @target && [Amnesia, Confusion, CharmPerson, CharmMonster, Fear].any? { |a| action.is_a? a }
        cancelled << action
        true
      end
    end

    if cancelled.length > 0
      cancelled.unshift self
      cancelled.each do |action|
        args.state.result << "Cancelled: #{action.description}"
      end
      return
    end

    @target.amnesia = true
    args.state.result << description
  end
end

class Fear < Spell
  @name = 'Fear'
  @default_target = :other
  @order = 17
  @type = :enchantment
end
class Confusion < Spell
  @name = 'Confusion'
  @default_target = :other
  @order = 18
  @type = :enchantment
end
class CharmMonster < Spell
  @name = 'Charm Monster'
  @default_target = :self
  @order = 19
  @type = :enchantment
end
class CharmPerson < Spell
  @name = 'Charm Person'
  @default_target = :other
  @order = 20
  @type = :enchantment
end
class Disease < Spell
  @name = 'Disease'
  @default_target = :other
  @order = 21
  @type = :enchantment
end
class Poison < Spell
  @name = 'Poison'
  @default_target = :other
  @order = 22
  @type = :enchantment
end
class CureLightWounds < Spell
  @name = 'Cure Light Wounds'
  @default_target = :self
  @order = 23
  @type = :protection
end
class CureHeavyWounds < Spell
  @name = 'Cure Heavy Wounds'
  @default_target = :self
  @order = 24
  @type = :protection
end
class AntiSpell < Spell
  @name = 'Anti Spell'
  @default_target = :other
  @order = 25
  @type = :enchantment
end
class Blindness < Spell
  @name = 'Blindness'
  @default_target = :other
  @order = 26
  @type = :enchantment
end
class Invisibility < Spell
  @name = 'Invisibility'
  @default_target = :self
  @order = 27
  @type = :enchantment
end
class Permanency < Spell
  @name = 'Permanency'
  @default_target = :self
  @order = 28
  @type = :enchantment
end
class DelayEffect < Spell
  @name = 'Delay Effect'
  @default_target = :self
  @order = 29
  @type = :enchantment
end
class RemoveEnchantment < Spell
  @name = 'Remove Enchantment'
  @default_target = :other
  @order = 30
  @type = :protection
end
class Shield < Spell
  @name = 'Shield'
  @default_target = :self
  @order = 31
  @type = :protection

  def resolve args
    args.state.result << description
    @target.shielded = true
  end
end
class MagicMissile < Spell
  @name = 'Magic Missile'
  @default_target = :other
  @order = 32
  @type = :damaging
end
class CauseLightWounds < Spell
  @name = 'Cause Light Wounds'
  @default_target = :other
  @order = 33
  @type = :damaging

  def resolve args
    @target.magical_damage 2
    args.state.result << description
  end
end
class CauseHeavyWounds < Spell
  @name = 'Cause Heavy Wounds'
  @default_target = :other
  @order = 34
  @type = :damaging
end
class LightningBolt < Spell
  @name = 'Lightning Bolt'
  @default_target = :other
  @order = 35
  @type = :damaging
end
class Fireball < Spell
  @name = 'Fireball'
  @default_target = :other
  @order = 36
  @type = :damaging
end
class FingerOfDeath < Spell
  @name = 'Finger of Death'
  @default_target = :other
  @order = 37
  @type = :damaging
end

class StormSpell < Spell
  class << self
    attr_reader :element
  end
end

class FireStorm < StormSpell
  @name = 'Fire Storm'
  @order = 38
  @type = :damaging
  @element = :fire
end
class IceStorm < StormSpell
  @name = 'Ice Storm'
  @order = 39
  @type = :damaging
  @element = :ice
end

class Stab < Action
  @name = 'stab'
  @default_target = :other
  @order = 40
end

class Nothing < Action
  @name = 'Nothing'
  @order = 41

  def resolve args
    # do nothing
  end
end

class Surrender < Action
  @name = 'surrender'
  @order = 42
end

Actions = [Nothing,DispelMagic,CounterSpell,MagicMirror,SummonGoblin,SummonOgre,SummonTroll,SummonGiant,SummonFireElemental,SummonIceElemental,RaiseDead,Haste,TimeStop,Protection,ResistHeat,ResistCold,Paralysis,Amnesia,Fear,Confusion,CharmMonster,CharmPerson,Disease,Poison,CureLightWounds,CureHeavyWounds,AntiSpell,Blindness,Invisibility,Permanency,DelayEffect,RemoveEnchantment,Shield,MagicMissile,CauseLightWounds,CauseHeavyWounds,LightningBolt,Fireball,FingerOfDeath,FireStorm,IceStorm,Stab,Surrender]
