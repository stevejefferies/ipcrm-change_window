require 'date'
require 'week_of_month'

# @summary
#   Provides change_window function that allows you to check current time against change window
Puppet::Functions.create_function(:'change_window::change_window') do
  # @param args
  #
  # @return [String]
  #   Returns true or false as string if the time is within the change window
  dispatch :default_impl do
    repeated_param 'Any', :args
  end

  def default_impl(*args)
    
    class << self
      def change_window_time_is_within(s,e,c)
        # Calculate by minutes of the week 0 ... 1439
        test = ((s[0].to_i*60+s[1].to_i)..(e[0].to_i*60+e[1])).cover?(c[0]*60+c[1])
        return test
      end

      def convert_string_to_int(s)
        begin
          return Integer(s, 10)
        rescue ArgumentError => ex
          raise Puppet::ParseError("window_month range values must be valid integers, got: #{s}")
        end
      end
    end

    # args[0] TimeZone
    # args[1] Window Type - per_day or window(default)
    # args[2] Hash, window_wday
    # args[3] Hash, window_time
    # args[4] Array, window_week (optional)
    # args[5] Array, window_month (optional)
    # args[6] String, Point-in-time to test (optional)

    # Configure start of week to be monday
    WeekOfMonth.configuration.monday_active = true

    # Validate Arguments are all present
    raise Puppet::ParseError, "Invalid argument count, got #{args.length} expected 4 or 5" unless (4..7).cover?(args.length)

    # Validate Args are correct type
    raise Puppet::ParseError, "TimeZone must be a string!"    unless args[0].is_a? String
    raise Puppet::ParseError, "Window type must be a string!" unless args[1].is_a? String
    raise Puppet::ParseError, "Window_wday must be a hash!"   unless args[2].is_a? Hash
    raise Puppet::ParseError, "Window_time must be a hash!"   unless args[3].is_a? Hash
    case args.length
    when 5
      raise Puppet::ParseError, "Window_week must be an array!" unless args[4].is_a? Array
    when 6
      raise Puppet::ParseError, "Window_month must be an array !" unless args[5].is_a? Array
    when 7
      raise Puppet::ParseError, "Point-in-time must be an array!" unless args[6].is_a? Array
    end

    # Set Timezone for other timestamp
    timezone = args[0]

    # Evaluation Type
    # per_day, or window
    # If per_day, we'll expect that window exists between start and end for each included
    # day.
    # If window, we'll expect that the window is continuous - from start day, start time through end day, end time.
    window_type = args[1].nil? ? 'window' : args[1]

    if !['window','per_day'].include?(window_type)
      raise Puppet::ParseError, "Window type must be 'window' or 'per_day'"
    end

    ## Setup months in year

    if args.length > 5
      window_month = []
      if not (args[5].is_a?(Array) && args[5].all? {|month| month.is_a?(Integer) || month.is_a?(String)})
        raise Puppet::ParseError, "window_month must be an array of integers or strings"
      end
      args[5].each do |val|
        if val.is_a?(Integer)
          if val.between?(1,12)
            window_month.push(val)
          else
            raise Puppet::ParseError, "window_month values must be between 1 and 12"
          end
        end
        if val.is_a?(String)
          range = val.split('-')
          if not range.length == 2
            raise Puppet::ParseError, "window_month values must be integers or string ranges in the form '1-3'"
          end
          start_month = convert_string_to_int(range[0])
          end_month = convert_string_to_int(range[1])
          if not (start_month <= end_month)
            raise Puppet::ParseError, "window_month range start month must be <= end month"
          end
          if not (start_month.between?(1,12) && end_month.between?(1,12))
            raise Puppet::ParseError, "window_month range must be between 1 and 12"
          end
          (start_month..end_month).each do |v|
            window_month.push(v)
          end
        end
      end
      window_month.uniq!
    else
      window_month = [1,2,3,4,5,6,7,8,9,10,11,12] # all months if arg not provided
    end


    ## Setup weeks in month # TODO: handle this as optional arg
    # Validate weeks provided are valid
    if not (args[4].is_a?(Array) && args[4].all? {|week| week.is_a?(Integer)})
      raise Puppet::ParseError, "window_week must be an array of integers"
    end
    #Validate weeks are within valid range
    if not (args[4].all? {|week| week.between?(1,5)})
      raise Puppet::ParseError, "window_weeks values must be between 1-5"
    end

    window_week = args[4].uniq # remove duplicates


    ## Setup the days of the week hash
    # First, validate that we got the keys we expect
    args[2].keys.each { |ww|
      if not ['start','end'].include?(ww)
        raise Puppet::ParseError, "The window_wday hash can include start and end only! Invalid value passed - #{ww}"
      end
    }

    # Now that we now we have valid keys, set local var equal to passed
    window_wday  = args[2]

    # Figure out what days have been passed & Convert non-int
    # Create new hash for storing ONLY int based days
    window_wday_int = Hash.new

    # For each day passed in, conver it from text to numeric
    # if numeric wasn't used
    for wdkey in window_wday.keys
      if window_wday[wdkey].is_a? String
        window_wday_int[wdkey] = Date::ABBR_DAYNAMES.map(&:downcase).find_index(window_wday[wdkey][0..2].downcase)
      elsif window_wday[wdkey].is_a? Integer
        window_wday_int[wdkey] = window_wday[wdkey]
      else
        raise Puppet::ParseError, "Invalid day found in supplied window days(its not a string or integer)"
      end
    end

    # One more validation - did we lookup valid values?
    window_wday_int.keys.each { |wi|
      if !window_wday_int[wi].is_a? Integer
        raise Puppet::ParseError, "Invalid day found in supplied window days"
      end

      if !(0..6).cover?(window_wday_int[wi])
        raise Puppet::ParseError, "Supplied weekday number is out of range (i.e. not 0-6) - value found #{window_wday_int[wi]}"
      end
    }

    ## Stores window start end time
    #24Hour #Minute
    #Example: {'start' => '17:00', 'end' => '23:00'}

    # Validate we got a usable time hash provided
    args[3].keys.each { |ts|
      if not ['start','end'].include?(ts)
        raise Puppet::ParseError, "Invalid key provided for window_time. Only start/end supported - found #{ts}"
      end

      if not args[3][ts] =~ /^\d(\d)?\:\d\d$/
        raise Puppet::ParseError, "Invalid time supplied for window_time #{ts} - found #{args[3][ts]}"
      end
    }

    # Now that we know its valid store it as a hash
    start_time = args[3]['start'].split(':').map(&:to_i)
    end_time   = args[3]['end'].split(':').map(&:to_i)
    window_time = {'start' => start_time, 'end' => end_time }
    window_time_str = {'start' => sprintf('%02d:%02d', start_time[0], start_time[1]),
      'end' => sprintf('%02d:%02d',end_time[0],end_time[1])}

    # Get Time (this will use localtime)
    if args.length != 7
      t = Time.now.getlocal(timezone)
    else
      raise Puppet::ParseError, "Invalid key for time expected 5 values and received #{args[6].length}" unless args[6].length == 5
      begin
        t = Time.new( *args[6], 0, timezone)
      rescue Exception
        # Catch exception and rebrand as parse error
        raise Puppet::ParseError, "Could not convert time array into valid Time.new object, received #{args[6].to_a}"
      end
    end

    # Build array of valid_days
    if window_wday_int['start'] > window_wday_int['end']
      # EOW-Wrap 4,1 = 4,5,6,0,1
      valid_days = (window_wday_int['start']..6).to_a + (0..window_wday_int['end']).to_a.uniq
    else
      # Within-EOW 1,4 = 1,2,3,4
      valid_days = (window_wday_int['start']..window_wday_int['end']).to_a.uniq
    end

    # Determine if we are within a valid month
    if window_month.include?(t.month)

      # Determine if we are within a valid week
      if window_week.include?(Date.parse(t.to_s).week_of_month)

        # Determine if today is within the valid days for the change window
        if valid_days.include?(t.wday)

          # IF this is the first day of the window
          if t.wday == window_wday_int['start'] and valid_days.length > 1
            # If window type or per_day with midnight wrap
            if window_type == 'window' or (window_type == 'per_day' and window_time_str['start'] > window_time_str['end'])
              # IF we are within <start time> and 23:59 return true
              window_time['end'] = [23,59]
            end
            change_window_time_is_within(window_time['start'],window_time['end'],[t.hour,t.min]) == true ? true.to_s : false.to_s

            # If this is the last day of the window
          elsif t.wday == window_wday_int['end'] and valid_days.length > 1

            # If window type or per_day with midnight wrap
            if window_type == 'window' or (window_type == 'per_day' and window_time_str['start'] > window_time_str['end'])
              #If we are within 00:00 and end
              window_time['start'] = [0, 0]
            end
            change_window_time_is_within(window_time['start'],window_time['end'],[t.hour,t.min]) == true ? true.to_s : false.to_s

            # If 1 day window type or per_day wo/ midnight wrap
          elsif (valid_days.length == 1 and window_type == 'window') or window_type == 'per_day'
            change_window_time_is_within(window_time['start'],window_time['end'],[t.hour,t.min]) == true ? true.to_s : false.to_s


            # midweek per_day
          elsif window_type == 'per_day'
            change_window_time_is_within(window_time['start'],window_time['end'],[t.hour,t.min]) == true ? true.to_s : false.to_s

            # Fall through matches window type and between window start/end
          else
            true.to_s
          end

          # Your not within the valid_days
        else
          false.to_s
        end

      else
        false.to_s
      end
    else
      false.to_s
    end
  end
end
