require 'monitor'

# use with:
# prepend ThreadSafeDefault

# this is better for objects that can be interacted with from the outside.
# use when the object should keep the local state coherent
# (atomic method calls)
module ThreadSafeDefault
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

# use with:
# include ThreadSafeClassWide
# thread_safe :method1, :method2

# this is better for interacting with the outside world, e.g. databases
module ThreadSafeClassWide
  def self.included(base)
    base.send :extend, ClassMethods
  end
  module ClassMethods
    def method_added(method_name)
      return if __hooks.nil? || !__hooks.include?(method_name)
      unless __hooked.include?(method_name)
        __hooked << method_name
        method_reference = instance_method(method_name)
        define_method(method_name) do |*args, &block|
          @__mutex ||= Mutex.new # this is class-wide!!!
          @__mutex.synchronize do
            method_reference.bind(self).call(*args, &block)
          end
        end
      end
    end

    def thread_safe(*method_names)
      @__hooks = method_names
    end

    def __hooked
      @__hooked ||= []
    end

    def __hooks
      @__hooks ||= []
    end
  end
end
