module Pliny::Endpoints
  class Root < Base
    get "/" do
      "hello."
    end
  end
end
