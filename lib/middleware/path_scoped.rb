module Middleware
  class PathScoped
    def initialize(app, middleware_class, *args, except:, &block)
      @app        = app
      @middleware = middleware_class.new(app, *args, &block)
      @except     = except
    end

    def call(env)
      env['PATH_INFO'].match?(@except) ? @app.call(env) : @middleware.call(env)
    end
  end
end
