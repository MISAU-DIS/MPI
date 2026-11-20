module Api
  module V1
    class DiagnosticsController < ApplicationController
      def show
        render json: DiagnosticsService.run
      end
    end
  end
end
