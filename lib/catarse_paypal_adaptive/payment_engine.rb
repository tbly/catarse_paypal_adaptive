module CatarsePaypalAdaptive
  class PaymentEngine

    def name
      'PayPal'
    end

    def review_path contribution
      CatarsePaypalAdaptive::Engine.routes.url_helpers.review_paypal_adaptive_path(contribution)
    end

    def can_do_refund?
      true
    end

    def direct_refund contribution
      CatarsePaypalAdaptive::ContributionActions.new(contribution).refund
    end

    def locale
      'en'
    end

  end
end
