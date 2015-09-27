module CatarsePaypalAdaptive
  class PaymentEngine

    def name
      'PayPal'
    end

    def review_path contribution
      CatarsePaypalAdaptive::Engine.routes.url_helpers.review_paypal_adaptive_path(contribution)
    end

    def can_do_refund? payment
      !payment.payment_processed?
    end

    # def direct_refund contribution
    #   CatarsePaypalAdaptive::ContributionActions.new(contribution).refund
    # end

    def direct_refund payment
      CatarsePaypalAdaptive::PaymentActions.new(payment).cancel_payment
    end

    def process_payment payment
      CatarsePaypalAdaptive::PaymentActions.new(payment).process_payment
    end

    def cancel_payment payment
      CatarsePaypalAdaptive::PaymentActions.new(payment).cancel_payment
    end

    def locale
      'en'
    end

  end
end
