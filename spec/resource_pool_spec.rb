require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "ResourcePool" do

  describe "Integration" do
    it "should work in small multithreaded environment" do
      pool = ResourcePool.new{ Hash.new }
      threads = []
      100.times do
        threads << Thread.new do
          pool.hold do |res|
            Thread.pass
            res.class.should == Hash
          end
        end
      end

      threads.each(&:join)
      pool.pool.size.should be_between(1, 4)
      pool.allocated.size.should == 0
    end

    it "should work in large multithreaded environment" do
      pool = ResourcePool.new(:max_size => 100){ Hash.new }
      threads = []
      1000.times do
        threads << Thread.new do
          pool.hold do |res|
            Thread.pass
            res.class.should == Hash
          end
        end
      end

      threads.each(&:join)
      pool.pool.size.should be_between(1, 1000)
      pool.allocated.size.should == 0
    end
  end

  describe "#size" do
    it "should return the size of pool plus allocated" do
      pool = ResourcePool.new{ Hash.new }
      pool.allocated.should_receive(:length).and_return(1)
      pool.pool.should_receive(:length).and_return(1)
      pool.size.should == 2
    end
  end

  describe "#create_resource" do
    it "should create new resource" do
      pool = ResourcePool.new{ Hash.new }
      res = pool.send :create_resource
      res.class.should == Hash
    end

    it "should raise error if create_proc returns nil" do
      pool = ResourcePool.new{ nil }
      lambda {
        pool.send :create_resource
      }.should raise_error(ResourcePool::InvalidCreateProc)
    end
  end

  describe "#salvage" do
    it "should salvage resources from dead thread" do
      pool = ResourcePool.new{ Hash.new }
      # create a dead thread
      thread = Thread.new{ nil }
      thread.join
      pool.allocated[thread] = Hash.new
      pool.send :salvage

      pool.allocated[thread].should be_nil
      pool.pool.length.should == 1
    end
  end

  describe "#make_new" do
    it "should invoke salvage if reach max size" do
      pool = ResourcePool.new{ Hash.new }
      pool.should_receive(:size).twice.and_return(4, 3)
      pool.should_receive(:salvage)
      pool.should_receive(:create_resource).and_return(Hash.new)

      pool.send(:make_new).class.should == Hash
    end

    it "should not invoke salvage if max size is not reached" do
      pool = ResourcePool.new{ Hash.new }
      pool.should_receive(:size).twice.and_return(3, 3)
      pool.should_not_receive(:salvage)
      pool.should_receive(:create_resource).and_return(Hash.new)

      pool.send(:make_new).class.should == Hash
    end

    it "should not invoke create_resouce if max size is reached" do
      pool = ResourcePool.new{ Hash.new }
      pool.should_receive(:size).twice.and_return(4, 4)
      pool.should_receive(:salvage)
      pool.should_not_receive(:create_resource)

      pool.send(:make_new).should == nil
    end
  end

  describe "#availabe" do
    it "should pop from pool" do
      pool = ResourcePool.new{ Hash.new }
      pool.pool.should_receive(:pop)
      pool.send(:available)
    end

    it "should use resource from pool if available" do
      res = {}
      pool = ResourcePool.new{ Hash.new }
      pool.pool.should_receive(:pop).and_return(res)
      pool.should_not_receive(:make_new)
      pool.send(:available).should == res
    end

    it "should invoke #make_new if pool is empty" do
      res = {}
      pool = ResourcePool.new{ Hash.new }
      pool.pool.should_receive(:pop).and_return(nil)
      pool.should_receive(:make_new).and_return(res)
      pool.send(:available).should == res
    end
  end

  describe "#release" do
    it "should remove resource from allocated and return to pool" do
      mock_thread = {}
      res = {}
      pool = ResourcePool.new{ Hash.new }
      pool.allocated.should_receive(:delete).
        with(mock_thread).
        and_return(res)
      pool.send :release, mock_thread
      pool.pool.first.should == res
    end
  end

  describe "#acquire" do
    it "should call #available" do
      mock_thread = {}
      res = {}
      pool = ResourcePool.new{ Hash.new }
      pool.should_receive(:available).once

      pool.send :acquire, mock_thread
    end

    it "should mark resource in use if resource is available" do
      mock_thread = {}
      res = {}
      pool = ResourcePool.new{ Hash.new }
      pool.should_receive(:available).and_return(res)
      pool.allocated.
        should_receive(:[]=).
        with(mock_thread, res).
        and_return(res)

      pool.send(:acquire, mock_thread).should == res
    end
  end

  describe "#owned_resource" do
    it "should return resouce of specified thread" do
      mock_thread = {}
      res = {}
      pool = ResourcePool.new{ Hash.new }
      pool.allocated.
        should_receive(:[]).
        with(mock_thread).
        and_return(res)
      pool.send(:owned_resource, mock_thread).should == res
    end

    it "should return nil if no resource was aquired" do
      mock_thread = {}
      pool = ResourcePool.new{ Hash.new }
      pool.allocated.
        should_receive(:[]).
        with(mock_thread).
        and_return(nil)
      pool.send(:owned_resource, mock_thread).should == nil
    end
  end

  describe "#release_all" do
    before :each do
      @pool = ResourcePool.new{ Hash.new }
      4.times{ @pool.pool << Hash.new }
    end

    it "should remove all resource from pool" do
      @pool.release_all
      @pool.size.should == 0
    end

    it "should call block if available" do
      counter = 0
      @pool.release_all{|res| counter += 1 }
      counter.should == 4
    end

    it "should call @delete_proc if no block given" do
      counter = 0
      delete_proc = lambda {|res| counter += 1 }
      @pool.instance_variable_set(:@delete_proc, delete_proc)
      @pool.release_all
      counter.should == 4
    end

    it "should call block if both block and @delete_proc are avaiable" do
      counter1 = 0
      counter2 = 0
      delete_proc = lambda {|res| counter1 += 1 }
      @pool.instance_variable_set(:@delete_proc, delete_proc)
      @pool.release_all{|res| counter2 += 1}
      counter1.should == 0
      counter2.should == 4
    end
  end

  describe "#hold" do
    before :each do
      @res = {}
      @pool = ResourcePool.new{ Hash.new }
    end

    it "should use already acquired resource" do
      @pool.should_receive(:owned_resource).
        with(Thread.current).
        and_return(@res)
      @pool.should_not_receive(:acquire)
      @pool.should_not_receive(:release)

      @pool.hold do |res|
        res.should == @res
      end
    end

    it "should aquire and release resource" do
      @pool.should_receive(:acquire).
        with(Thread.current).
        and_return(@res)
      @pool.should_receive(:release).
        with(Thread.current)

      @pool.hold do |res|
        res.should == @res
      end
    end

    it "should retry aquire" do
      args = []
      1000.times{ args << nil }
      args << @res
      @pool.should_receive(:acquire).
        and_return(*args)

      start = Time.now
      @pool.hold do |res|
        res.should == @res
      end
      delta = Time.now - start
      delta.should be_between(0.8, 1.2)
    end

    it "should timeout after 2 seconds" do
      @pool.should_receive(:acquire).
        any_number_of_times.
        and_return(nil)
      @pool.should_not_receive(:release)

      start = Time.now
      lambda {
        @pool.hold{ |res| res.should == @res }
      }.should raise_error(ResourcePool::PoolTimeout)

      delta = Time.now - start
      delta.should be_between(1.99, 2.01)
    end

    it "should delete bad resource" do
      @pool.should_receive(:acquire).
        and_return(@res)
      @pool.should_not_receive(:release)
      @pool.allocated.should_receive(:delete).
        with(Thread.current)

      lambda {
        @pool.hold{ |res| raise ResourcePool::BadResource }
      }.should raise_error(ResourcePool::BadResource)
    end

    it "should call delete_proc if avaiable" do
      delete_proc_called = false
      @pool.should_receive(:acquire).
        and_return(@res)
      @pool.should_not_receive(:release)
      @pool.allocated.should_receive(:delete).
        with(Thread.current)

      @pool.instance_variable_set(:@delete_proc, lambda{|res|
        delete_proc_called = true
      })

      lambda {
        @pool.hold{ |res| raise ResourcePool::BadResource }
      }.should raise_error(ResourcePool::BadResource)

      delete_proc_called.should be_true
    end
  end
end
