Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  get "bookmarks/search", controller: :bookmarks, action: :search, as: :bookmarks_search
  get "bookmarks/tagged_with/:tags", controller: :bookmarks, action: :tagged_with, as: :bookmarks_tagged_with
  get "bookmarks/unarchived", controller: :bookmarks, action: :unarchived, as: :bookmarks_unarchived
  get "bookmarks/to_read", controller: :bookmarks, action: :to_read, as: :bookmarks_to_read

  # a trivially small success page which expects to be closed immediately
  # by the plugin
  get "bookmarks/success", controller: :bookmarks, action: :success, as: :bookmarks_success

  resources :bookmarks do
    member do
      put "archive"
    end
  end



  # Defines the root path route ("/")
  root "bookmarks#index"


  match "/debugging/echo" => "debugging#echo", via: [:get, :post, :put, :patch, :delete]
end
