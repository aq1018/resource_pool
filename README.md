# resource_pool

[![Gem Version](https://badge.fury.io/rb/resource_pool.png)](http://badge.fury.io/rb/resource_pool)
[![Build Status](https://travis-ci.org/aq1018/resource_pool.png?branch=master)](https://travis-ci.org/aq1018/resource_pool)
[![Dependency Status](https://gemnasium.com/aq1018/resource_pool.png)](https://gemnasium.com/aq1018/resource_pool)
[![Code Climate](https://codeclimate.com/badge.png)](https://codeclimate.com/github/aq1018/resource_pool)

This is a generic connection pool / resource pool implementation. The initial code is largely taken from `ThreadedConnectionPool` class from `Sequel` gem and adapted for more general use.


## Install

```
  gem install resource_pool
```

## Usage

```ruby
  require 'resource_pool'

  memcache_pool = ResourcePool.new({
      :max_size => 10,                  # Max amount of resource allowed to create. Default is 4
      :pool_timeout => 4,               # Seconds to wait when aquiring a free resource.
                                        # Set to 0 to skip waiting. Default is 2
      :pool_sleep_time => 0.1,          # Seconds to wait for retry aquiring resource. Default is 0.001
      :delete_proc => lambda{ |res| }   # a proc used to close / delete the resource. Optional
  }) do
    # create your resource here.
    # A resource can be anything such as TCP, persistent HTTP, database, nosql
    # Note: must return the instantiated resource
    Memcache.new MemCache.new 'host:11211'
  end

  # using defaults for redis pool
  redis_pool = ResourcePool.new do
    Redis.new(:host => "10.0.1.1", :port => 6380)
  end

  # Use the resource:
  threads = []
  50.times do
    thread = Thread.new do
      # there are 4 redis connections
      # can now be shared safely with 50 threads
      redis_pool.hold do |redis|
        redis.set "foo", "bar"
        redis.get "foo"
      end
    end
    threads << thread
  end

  threads.each(&:join)
```

## Contributing to resource_pool

* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it
* Fork the project
* Start a feature/bugfix branch
* Commit and push until you are happy with your contribution
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2011 Aaron Qian. See LICENSE.txt for
further details.

