class ResourcePool
  class ResourcePoolError < RuntimeError; end
  class ResourceNotAvailable < ResourcePoolError; end
  class InvalidCreateProc < ResourcePoolError; end

  attr_reader :max_size, :pool, :allocated

  def initialize(opts={}, &block)
    @max_size = opts[:max_size] || 4
    @create_proc = block
    @pool = []
    @allocated = {}
    @mutex = Mutex.new
    @timeout = opts[:pool_timeout] || 2
    @sleep_time = opts[:pool_sleep_time] || 0.001
    @delete_proc = opts[:delete_proc]
  end

  def size
    @allocated.length + @pool.length
  end

  def release_all(&block)
    block ||= @delete_proc
    sync do
      @pool.each{|res| block.call(res)} if block
      @pool.clear
    end
  end

  def hold
    t = Thread.current
    if res = owned_resource(t)
      return yield(res)
    end

    begin
      unless res = acquire(t)
        raise ResourceNotAvailable if @timeout == 0
        time = Time.now
        timeout = time + @timeout
        sleep_time = @sleep_time
        sleep sleep_time
        until res = acquire(t)
          raise ResourceNotAvailable if Time.now > timeout
          sleep sleep_time
        end
      end
      yield res
    ensure
      sync{release(t)} if owned_resource(t)
    end
  end

  # please only call this inside hold block
  def trash_current!
    t    = Thread.current
    conn = owned_resource(t)
    return unless conn

    @delete_proc.call conn if @delete_proc
    sync { @allocated.delete(t) }
    nil
  end

  private

  def owned_resource(thread)
    sync{ @allocated[thread] }
  end

  def acquire(thread)
    sync do
      res = available
      @allocated[thread] = res if res
    end
  end

  def release(thread)
    @pool << @allocated.delete(thread)
  end

  def available
    @pool.pop || make_new
  end

  def make_new
    salvage if size >= @max_size
    size < @max_size ? create_resource : nil
  end

  def salvage
    @allocated.keys.each{ |t| release(t) unless t.alive? }
  end

  def create_resource
    resource = @create_proc.call
    raise InvalidCreateProc, "create_proc returned nil" unless resource
    resource
  end

  def sync
    @mutex.synchronize{yield}
  end
end
