import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import resetPassword from '@salesforce/apex/PasswordManager.resetPassword';
import validateResetPasswordToken from '@salesforce/apex/PasswordManager.validateResetPasswordToken';
import Arelia_Site_Redirect_URL_Label from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label';

export default class ResetPasswordPage extends LightningElement {
    token;
    password = '';
    confirmPassword = '';
    message;
    passwordType = 'password';
    showModal = false;
    isValidToken = false;

    strengthText = '';
    strengthClass = '';
    ruleLength = '';
    ruleNumber = '';
    ruleUpper = '';
    ruleSpecial = '';

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference?.state?.token) {
            this.token = currentPageReference.state.token;
            this.validateToken();
        }
    }

    validateToken() {
        validateResetPasswordToken({ token: this.token })
            .then(result => {
                if (result === 'VALID') {
                    this.isValidToken = true;
                    this.message = null;
                } else if (result === 'EXPIRED') {
                    this.message = 'This link has expired.';
                } else {
                    this.message = 'You have already set your password or link is invalid.';
                }
            })
            .catch(() => {
                this.message = 'Error validating link.';
            });
    }

    handleChange(event) {
        this.password = event.target.value;
        this.evaluatePassword(this.password);
    }

    setFieldError(message) {
        const confirmInput = this.template.querySelector('[data-id="confirmPassword"]');
        const newInput = this.template.querySelector('[data-id="newPassword"]');

        if (confirmInput) {
            confirmInput.setCustomValidity(message);
            confirmInput.reportValidity();
        }

        if (newInput) {
            newInput.setCustomValidity(message);
            newInput.reportValidity();
        }
    }

    clearFieldError() {
        const confirmInput = this.template.querySelector('[data-id="confirmPassword"]');
        const newInput = this.template.querySelector('[data-id="newPassword"]');

        if (confirmInput) {
            confirmInput.setCustomValidity('');
            confirmInput.reportValidity();
        }

        if (newInput) {
            newInput.setCustomValidity('');
            newInput.reportValidity();
        }
    }

    handleConfirmChange(event) {
        this.confirmPassword = event.target.value;

        if (this.password && this.confirmPassword !== this.password) {
            this.setFieldError('Passwords do not match.');
        } else {
            this.clearFieldError();
        }
    }

    togglePassword(event) {
        this.passwordType = event.target.checked ? 'text' : 'password';
    }

    evaluatePassword(pwd) {
        let score = 0;

        const hasLength = pwd.length >= 6;
        const hasNumber = /\d/.test(pwd);
        const hasUpper = /[A-Z]/.test(pwd);
        const hasSpecial = /[$%@#!^&*]/.test(pwd);

        this.ruleLength = hasLength ? 'valid' : 'invalid';
        this.ruleNumber = hasNumber ? 'valid' : 'invalid';
        this.ruleUpper = hasUpper ? 'valid' : 'invalid';
        this.ruleSpecial = hasSpecial ? 'valid' : 'invalid';

        if (hasLength) score++;
        if (hasNumber) score++;
        if (hasUpper) score++;
        if (hasSpecial) score++;

        if (pwd.length === 0) {
            this.strengthText = '';
            this.strengthClass = '';
        } else if (score <= 1) {
            this.strengthText = 'Weak';
            this.strengthClass = 'strength-weak';
        } else if (score === 2 || score === 3) {
            this.strengthText = 'Medium';
            this.strengthClass = 'strength-medium';
        } else {
            this.strengthText = 'Strong';
            this.strengthClass = 'strength-strong';
        }
    }

    handleSubmit() {
        if (!this.password || !this.confirmPassword) {
            this.setFieldError('Please complete all required fields.');
            return;
        }

        if (this.password !== this.confirmPassword) {
            this.setFieldError('Passwords do not match.');
            return;
        } else {
            this.clearFieldError();
        }

        const isValidPassword =
            this.password.length >= 6 &&
            /\d/.test(this.password) &&
            /[A-Z]/.test(this.password) &&
            /[$%@#!^&*]/.test(this.password);

        if (!isValidPassword) {
            this.setFieldError('Password must meet all requirements.');
            return;
        } else {
            this.clearFieldError();
        }

        resetPassword({
            token: this.token,
            newPassword: this.password
        })
            .then(() => {
                this.showModal = true;
                this.message = null;
            })
            .catch(error => {
                this.message = error.body?.message || 'Error resetting password.';
            });
    }

    closeModal() {
        this.showModal = false;
        this.password = '';
        this.confirmPassword = '';

        const redirectUrl = (Arelia_Site_Redirect_URL_Label || '').trim();
        if (redirectUrl) {
            window.location.assign(redirectUrl);
        }
    }
}