Rails.application.config.middleware.insert_before 0, Rack::Cors do
 allow do
   origins "*"

   resource "/api/*", **{
     headers: :any,
     expose:  %w[Link Current-Page Page-Items Total-Pages Total-Count],
     methods: %i[get post put patch delete options head]
   }
 end
end
