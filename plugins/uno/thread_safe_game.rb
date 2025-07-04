require 'monitor'

# Optional thread safety module for UnoGame
# Can be included when thread safety is needed (e.g., in IRC bot context)
module ThreadSafeGame
  def initialize(*original_args)
    super(*original_args)
    @__monitor = Monitor.new
    self.class.instance_methods(false).each do |method_name|
      method_reference = self.class.instance_method(method_name)
      define_singleton_method method_name do |*args, &block|
        @__monitor.synchronize do
          method_reference.bind(self).call(*args, &block)
        end
      end
    end
  end
end