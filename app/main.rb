require 'lib/actions'

def tick args
  args.state.options ||= Actions.map(&:name)

  args.state.west ||= Warlock.new('West', :w, :s, :d)
  args.state.east ||= Warlock.new('East', :up, :down, :left)
  args.state.beings ||= [args.state.west, args.state.east]

  args.state.result ||= []

  # Overall game loop structure:
  #
  # check if time stop turn
  # else if haste turn but no one has haste, skip haste turn
  #
  # simultaneous for each warlock:
  #   if previously cast paralyze, choose paralyzed hand
  #   if previously cast charm person, choose charmed hand and gesture
  #   for each hand:
  #     choose gesture (will be ignored if hand paralyzed/charmed)
  #     choose spell
  #     choose target
  #     choose delay (if allowed)
  #     choose permanent (if allowed)
  #   choose to fire delayed spell (if delayed on previous turn)
  #   for each controlled monster and for each monster you _could_ control via spells:
  #     choose monster's target
  #
  # if any warlocks are confused, randomly choose hand, gesture, and spell (default target)
  #
  # resolve all actions
  # check for surrender
  # check for time stop

  # is this a time stop turn?
  time_stopped = args.state.beings.any? { |b| b.time_stopped }

  # if this is a haste turn, but no one has haste, skip it
  if !time_stopped && args.state.haste && args.state.beings.all? { |b| !b.haste? }
    args.state.haste = false
  end

  # if this is the start of a normal turn
  if !time_stopped && !args.state.haste
    # clear all warlocks' paralysis targets
    args.state.beings.each do |being|
      next unless being.is_a? Warlock
      being.paralysis_target = nil
    end

    args.state.beings.each do |being|
      # if a warlock was paralyzed, need to paralyze one of their hands _after_ the tick
      paralyzed_hand = nil
      if being.is_a?(Warlock) && being.paralyzed_this_turn
        # if previously paralyzed, the same hand continues to be paralyzed
        unless paralyzed_hand = being.paralyzed_hand
          if being.paralyzed_by.is_a? Warlock
            # store target so they can choose the hand after
            being.paralyzed_by.paralysis_target = being
          else
            raise "somehow failed to select paralyzed hand for non-warlock caster"
          end
        end
      end

      being.tick

      # tick clears paralysis, retain it if needed
      being.paralyzed_hand = paralyzed_hand if paralyzed_hand
    end
  end

  # get all inputs from warlocks and see if they're ready
  # TODO: get paralysis input first, if needed
  wizard_acted = false
  both_ready = [args.state.west, args.state.east].map do |warlock|
    # if this is a time stop or haste turn, but this warlock doesn't have it, skip them
    if (time_stopped && !warlock.time_stopped) || (!time_stopped && args.state.haste && !warlock.haste?)
      next true
    end

    # order is:
    # 1. left hand spell
    # 2. left hand target
    # 3. right hand spell
    # 4. right hand target
    # 5. repeat

    # are we on step 1, 3, or 5? choose a spell
    if warlock.choices.empty? || warlock.ready_to_resolve || (warlock.choices.length == 1 && warlock.targets.length == 1)
      # change selection in action menu
      if args.inputs.keyboard.key_down.send(warlock.up)
        warlock.index -= 1
      end
      if args.inputs.keyboard.key_down.send(warlock.down)
        warlock.index += 1
      end
      warlock.index %= args.state.options.length

      # select current action
      if args.inputs.keyboard.key_down.send(warlock.select)
        # if we're choosing left hand, clear in case they restarted selection
        if warlock.targets.length != 1
          warlock.clear_input
        end
        warlock.choices << warlock.index

        # target is next, so reset index based on default target
        # no default target is set to self
        default_target =
          if args.state.west.index == 0
            :self
          else
            Actions[warlock.index].default_target || :self
          end

        warlock.index = args.state.beings.index do |being|
          (default_target == :self && being == warlock) || (default_target == :other && being.is_a?(Warlock) && being != warlock)
        end
      end
    elsif warlock.targets.length < 2 # are we on step 2 or 4?
      # change selection in being menu
      if args.inputs.keyboard.key_down.send(warlock.up)
        warlock.index -= 1
      end
      if args.inputs.keyboard.key_down.send(warlock.down)
        warlock.index += 1
      end
      warlock.index %= args.state.beings.length

      # select current being
      if args.inputs.keyboard.key_down.send(warlock.select)
        warlock.targets << args.state.beings[warlock.index]
        warlock.index = 0
      end
    end
    wizard_acted = true
    warlock.ready_to_resolve
  end.all?

  # resolve actions
  if both_ready
    actions = []
    [args.state.west, args.state.east].each do |warlock|
      warlock.choices.each_with_index do |i, j|
        next unless i >= 0

        action = Actions[i]
        actions << action.new(warlock, warlock.targets[j])
      end
    end

    args.state.actions = actions.sort
    # clear resolution if a wizard acted (it means we already saw what happened previously)
    if wizard_acted
      args.state.result = []
    end

    # all monster attacks go last
    args.state.beings.each do |being|
      if (time_stopped && !being.time_stopped) || (!time_stopped && args.state.haste && !being.haste?)
        next
      end
      if being.is_a?(Monster) && being.health > 0
        args.state.actions << being.attack
      end
    end

    # resolve each action
    while action = args.state.actions.shift
      action.resolve args
    end

    # health can go below min or above max to handle simultaneous resolution, now it should clamp
    args.state.beings.each do |being|
      being.clamp_health
    end

    # clear spell selection
    args.state.west.choices = []
    args.state.east.choices = []

    # check if anyone stopped time this turn
    time_stopped = false
    args.state.beings.each do |being|
      time_stopped ||= being.time_stop
      being.time_stopped = being.time_stop
      being.time_stop = false
    end

    # resolve opposite turn type next
    unless time_stopped
      args.state.haste = !args.state.haste
    end
  end

  [[args.state.west, 0, 1, 0], [args.state.east, 1280, -1, 2]].each do |warlock, edge, shift, alignment|
    args.outputs.labels << [edge + shift * 10, 660, "#{warlock.name}: " + warlock.choices.map { |i| args.state.options[i] }.join(', '), 6, alignment]

    choices =
      if warlock.choices.empty? || warlock.ready_to_resolve || (warlock.choices.length == 1 && warlock.targets.length == 1)
        args.state.options
      elsif warlock.targets.length < 2
        args.state.beings.map(&:name)
      end

    (-5..5).each do |o|
      i = (warlock.index + o) % choices.length
      args.outputs.labels << [edge + shift * 10, 360 - o * 40, choices[i], 5, alignment, o == 0 ? 255 : 0, 0, 0]
    end
  end

  # draw previous resolution
  args.state.result.each_with_index do |r, i|
    args.outputs.labels << [640, 700 - i * 40, r, 3, 1]
  end

end
