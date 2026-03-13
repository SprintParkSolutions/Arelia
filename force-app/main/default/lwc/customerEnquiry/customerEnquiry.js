import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import sendVerificationEmail from '@salesforce/apex/RegistrationFormController.sendVerificationEmail';
import registerLead from '@salesforce/apex/RegistrationFormController.registerLead';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const RESEND_COOLDOWN_SECONDS = 60;
const OTP_VALIDITY_MS = 60 * 1000;

export default class CustomerEnquiry extends LightningElement {
    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track phone = '';
    @track countryCode = '+91';
    countryCodeOptions = [
        { label: '+91 India', value: '+91' },
        { label: '+1 United States', value: '+1' },
        { label: '+44 United Kingdom', value: '+44' }
    ];

    @track showStep1 = true;
    @track showStep2 = false;

    @track otpInput = '';
    @track emailVerified = false;
    @track isSendingCode = false;
    @track isSubmitting = false;

    @track resendTimer = 0;
    timerId;
    generatedOtp;
    otpExpiresAt;
    showSuccessScreen = false;

    // getters
    get isEmailValid() {
        return EMAIL_REGEX.test((this.email || '').trim());
    }
    get isPhoneValid() {
        const digits = (this.phone || '').replace(/\D/g, '');
        return digits.length === 10;
    }
    get isNextDisabled() {
        return this.isSubmitting || !this.firstName || !this.lastName || !this.isEmailValid || !this.isPhoneValid;
    }
    get isButtonDisabled() {
        return this.isSubmitting || !this.emailVerified;
    }
    get disableVerifyButton() {
        return !this.generatedOtp || !this.otpInput || this.emailVerified;
    }
    get resendTimerActive() {
        return this.resendTimer > 0;
    }
    get sendCodeButtonLabel() {
        if (!this.generatedOtp) return 'Send Code';
        return this.resendTimerActive ? `Resend in ${this.resendTimer}s` : 'Resend Code';
    }
    get isSendCodeDisabled() {
        return this.isSendingCode || this.resendTimerActive || !this.isEmailValid;
    }

    // native input handlers
    handleNativeInput(event) {
        const name = event.target.name;
        const value = event.target.value;
        if (name === 'firstName') this.firstName = value;
        else if (name === 'lastName') this.lastName = value;
        else if (name === 'email') this.email = value;
        else if (name === 'phone') this.phone = value;
    }

    handleCountryChange(event) {
        // select change uses event.target.value with native select
        this.countryCode = event.target.value;
    }

    handleNativeOtp(event) {
        this.otpInput = event.target.value;
    }

    // navigation
    goToVerification() {
        // Validate fields and show toast messages if needed
        let emailMsg = '';
        if (!this.email) emailMsg = 'Email is required.';
        else if (!this.isEmailValid) emailMsg = 'Enter a valid email address.';

        const digits = (this.phone || '').replace(/\D/g, '');
        let phoneMsg = '';
        if (!digits) phoneMsg = 'Mobile number is required.';
        else if (digits.length !== 10) phoneMsg = 'Enter a 10-digit mobile number.';

        if (emailMsg || phoneMsg || !this.firstName || !this.lastName) {
            if (!this.firstName || !this.lastName) {
                this.showToast('Error', 'First and Last name are required.', 'error');
            } else if (emailMsg) {
                this.showToast('Error', emailMsg, 'error');
            } else {
                this.showToast('Error', phoneMsg, 'error');
            }
            return;
        }

        // go to step 2
        this.showStep1 = false;
        this.showStep2 = true;
    }

    backToStep1() {
        this.showStep2 = false;
        this.showStep1 = true;
        this.clearResendTimer();
        this.generatedOtp = null;
        this.otpInput = '';
        this.emailVerified = false;
    }

    // OTP
    handleSendCode() {
        if (!this.isEmailValid) {
            this.showToast('Error', 'Enter a valid email before sending code.', 'error');
            return;
        }
        this.isSendingCode = true;
        this.emailVerified = false;
        this.generatedOtp = this.generateOtp();
        this.otpExpiresAt = Date.now() + OTP_VALIDITY_MS;

        sendVerificationEmail({ email: this.email, verificationCode: this.generatedOtp })
            .then(() => {
                this.showToast('Success', 'Verification code sent to your email.', 'success');
                this.startResendCountdown();
            })
            .catch((error) => {
                this.generatedOtp = null;
                this.otpExpiresAt = null;
                this.clearResendTimer();
                this.handleApexError(error, 'Failed to send verification code.');
            })
            .finally(() => {
                this.isSendingCode = false;
            });
    }

    handleVerifyCode() {
        if (!this.generatedOtp) {
            this.showToast('Error', 'Please click "Send Code" first.', 'error');
            return;
        }
        if (this.otpExpiresAt && Date.now() > this.otpExpiresAt) {
            this.showToast('Error', 'Verification code has expired. Please resend a new code.', 'error');
            this.generatedOtp = null;
            this.otpExpiresAt = null;
            this.otpInput = '';
            this.emailVerified = false;
            return;
        }
        if (!this.otpInput) {
            this.showToast('Error', 'Please enter the verification code.', 'error');
            return;
        }
        if (this.otpInput === this.generatedOtp) {
            this.emailVerified = true;
            this.showToast('Success', 'Email verified successfully.', 'success');
        } else {
            this.emailVerified = false;
            this.showToast('Error', 'Invalid verification code. Please try again.', 'error');
        }
    }

    // submit
    handleSubmit() {
        if (!this.emailVerified) {
            this.showToast('Error', 'Please verify your email before sending the enquiry.', 'error');
            return;
        }
        if (!this.firstName || !this.lastName) {
            this.showToast('Error', 'First and Last name are required.', 'error');
            return;
        }
        this.isSubmitting = true;
        const fullPhone = this.countryCode ? `${this.countryCode} ${this.phone}` : this.phone;
        const payload = {
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email,
            phone: fullPhone
        };
        registerLead({ payload })
            .then(() => {
                this.showSuccessScreen = true;
                this.showStep2 = false;
                this.showStep1 = true;
                this.resetForm();
            })
            .catch((error) => {
                this.handleApexError(error, 'Failed to submit enquiry. Please try again.');
            })
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    // timers + utils
    startResendCountdown() {
        this.clearResendTimer();
        this.resendTimer = RESEND_COOLDOWN_SECONDS;
        this.timerId = window.setInterval(() => {
            if (this.resendTimer <= 1) this.clearResendTimer();
            else this.resendTimer -= 1;
        }, 1000);
    }
    clearResendTimer() {
        if (this.timerId) { clearInterval(this.timerId); this.timerId = undefined; }
        this.resendTimer = 0;
    }
    generateOtp() {
        const code = Math.floor(100000 + Math.random() * 900000);
        return String(code);
    }

    resetForm() {
        this.firstName = '';
        this.lastName = '';
        this.email = '';
        this.phone = '';
        this.countryCode = '+91';
        this.otpInput = '';
        this.generatedOtp = null;
        this.otpExpiresAt = null;
        this.emailVerified = false;
        this.clearResendTimer();
    }

    handleCloseSuccess() { this.showSuccessScreen = false; }
    handleApexError(error, fallbackMessage) {
        let message = fallbackMessage;
        if (error && error.body && error.body.message) message = error.body.message;
        this.showToast('Error', message, 'error');
    }
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}