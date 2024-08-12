Rails.application.config.middleware.insert_before 0, Rack::Cors do
 allow do
   origins "*"
   resource "/api/*", **{
     headers: :any,
     expose:  %w[Link],
     methods: %i[get post put patch delete options head]
   }
 end
end
