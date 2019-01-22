require 'hkp'
require 'mail/gpg/delivery_handler'
require 'mail/gpg/verify_result_attribute'

module Mail
  module Gpg
    module MessagePatch

      def self.included(base)
        base.class_eval do
          attr_accessor :raise_encryption_errors
          include VerifyResultAttribute
        end
      end

      # turn on gpg encryption / set gpg options.
      #
      # options are:
      #
      # encrypt: encrypt the message. defaults to true
      # sign: also sign the message. false by default
      # sign_as: UIDs to sign the message with
      #
      # See Mail::Gpg methods encrypt and sign for more
      # possible options
      #
      # mail.gpg encrypt: true
      # mail.gpg encrypt: true, sign: true
      # mail.gpg encrypt: true, sign_as: "other_address@host.com"
      #
      # sign-only mode is also supported:
      # mail.gpg sign: true
      # mail.gpg sign_as: 'jane@doe.com'
      #
      # To turn off gpg encryption use:
      # mail.gpg false
      #
      def gpg(options = nil)
        case options
        when nil
          @gpg
        when false
          if Mail::Gpg::DeliveryHandler == delivery_handler
            self.delivery_handler = @gpg[:delivery_handler]
          end
          @gpg = nil
          nil
        else
          self.raise_encryption_errors = true if raise_encryption_errors.nil?
          @gpg = {delivery_handler: self.delivery_handler}.merge(options)
          self.delivery_handler = Mail::Gpg::DeliveryHandler
          nil
        end
      end

      # true if this mail is encrypted
      def encrypted?
        Mail::Gpg.encrypted?(self)
      end

      # returns the decrypted mail object.
      #
      # pass verify: true to verify signatures as well. The gpgme verification
      # result will be available via decrypted_mail.verify_result
      def decrypt(options = {})
        import_missing_keys = options[:verify] && options.delete(:import_missing_keys)
        Mail::Gpg.decrypt(self, options).tap do |decrypted|
          if import_missing_keys && !decrypted.signature_valid?
            import_keys_for_signatures! decrypted.signatures
            return Mail::Gpg.decrypt(self, options)
          end
        end
      end

      # true if this mail is signed (but not encrypted)
      def signed?
        Mail::Gpg.signed?(self)
      end

      # verify signatures. returns a new mail object with signatures removed and
      # populated verify_result.
      #
      # verified = signed_mail.verify()
      # verified.signature_valid?
      # signers = mail.signatures.map{|sig| sig.from}
      #
      # use import_missing_keys: true in order to try to fetch and import
      # unknown keys for signature validation
      def verify(options = {})
        import_missing_keys = options.delete(:import_missing_keys)
        Mail::Gpg.verify(self, options).tap do |verified|
          if import_missing_keys && !verified.signature_valid?
            import_keys_for_signatures! verified.signatures
            return Mail::Gpg.verify(self, options)
          end
        end
      end

      def import_keys_for_signatures!(signatures = [])
        hkp = Hkp.new raise_errors: false
        signatures.each do |sig|
          begin
            sig.key
          rescue EOFError # gpgme throws this for unknown keys :(
            hkp.fetch_and_import sig.fingerprint
          end
        end
      end


    end
  end
end

unless Mail::Message.included_modules.include?(Mail::Gpg::MessagePatch)
  Mail::Message.send :include, Mail::Gpg::MessagePatch
end
