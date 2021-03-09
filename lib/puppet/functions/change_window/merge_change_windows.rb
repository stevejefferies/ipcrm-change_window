require 'date'

# @summary
#   Creates complex change windows by merging a series of windows together
Puppet::Functions.create_function(:'change_window::merge_change_windows') do
  # @param args
  #
  # @return [String]
  #   Returns true or false as string if the time is within the merged change window
  dispatch :default_impl do
    repeated_param 'Any', :args
  end

  def default_impl(*args)
    

    # Validate arguments
    raise Puppet::ParseError, "Invalid argument count, got #{args.length} and expected 1" unless args.length == 1
    raise Puppet::ParseError, "Change_windows must be an array!" unless args[0].is_a? Array

    in_cw = false
    args[0].each { |cw|
      raise Puppet::ParseError, "Expect an Array for change_window entry, received #{cw.class}" unless cw.is_a? Array
      begin
        if call_function('change_window::change_window', *cw) == 'true'
          in_cw = true
        else
        end
      rescue Exception => e
        # Catch exception and rebrand it as ours
        raise Puppet::ParseError, "Call to change_window threw #{e.message}"
      end
    }
    return in_cw.to_s
  
  end
end
