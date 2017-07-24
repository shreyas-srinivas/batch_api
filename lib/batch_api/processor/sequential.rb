require 'json'
require 'liquid'
module BatchApi
  class Processor
    class Sequential
      # Public: initialize with the app.
      SUCCESS_CODES = (200..299).freeze

      def initialize(app)
        @app = app
        @json_results = []
      end

      # Public: execute all operations sequentially.
      #
      # ops - a set of BatchApi::Operations
      # options - a set of options
      #
      # Returns an array of BatchApi::Response objects.
      def call(env)
        env[:ops].collect do |op|
          if env[:options]["dependencies"] && op.depends_on.any?
            msg, err = resolve_dependencies(op)
            if err
              next BatchApi::Response.new([422, {}, [{ "error" => msg }.to_json]])
            end
          end
          
          # set the current op
          env[:op] = op
          
          # execute the individual request inside the operation-specific
          # middeware, then clear out the current op afterward
          middleware = InternalMiddleware.operation_stack
          middleware.call(env).tap { |r|
            env.delete(:op)
            # r.body = JSON.parse(r.body)
            if env[:options]["dependencies"]
              if SUCCESS_CODES.include?(r.status)
                @json_results << r.body
              else
                @json_results << {errors: true}
              end
            end
          }
        end
      end

      def resolve_dependencies(op)
        if op.depends_on.detect { |d_on| @json_results[d_on][:errors] }
          return ["One of dependent requests failed", true]
        end
        begin
          op.url = Liquid::Template.parse(op.url).render!('data' => @json_results)
          op.params = JSON.parse(Liquid::Template.parse(op.params.to_json).render!('data' => @json_results))
          op.headers = JSON.parse(Liquid::Template.parse(op.headers.to_json).render!('data' => @json_results))
        rescue Exception => e 
          ["Please check your placeholders", true]
        end
      end
    end
  end
end

