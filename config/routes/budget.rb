resources :budgets, only: [:show, :index, :stats] do
  resources :groups, controller: "budgets/groups", only: [:show]
  resources :investments, controller: "budgets/investments", only: [:index, :new, :create, :show, :destroy] do
    member     { post :vote }
    collection { get :suggest }
  end

  resource :ballot, only: :show, controller: "budgets/ballots" do
    resources :lines, controller: "budgets/ballot/lines", only: [:create, :destroy]
  end

  resource :results, only: :show, controller: "budgets/results"


  get :stats
  get :progress_1
  get :progress_2
end

scope '/participatory_budget' do
  resources :spending_proposals, only: [:index, :new, :create, :show, :destroy], path: 'investment_projects' do
    post :vote, on: :member
  end
end
