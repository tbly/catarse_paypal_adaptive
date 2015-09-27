CatarsePaypalAdaptive::Engine.routes.draw do
  resources :paypal_adaptive, only: [], path: 'payment/paypal_adaptive' do
    collection do
      post :ipn
    end

    member do
      get  :review
      post :pay
      get  :success
      get  :cancel
      get  :payment_callback
    end
  end
end

