import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import setPassword from '@salesforce/apex/PasswordManager.setPassword';
import validateSetPasswordToken from '@salesforce/apex/PasswordManager.validateSetPasswordToken';
import AreliaSiteRedirectUrlLabel from '@salesforce/label/c.Arelia_Site_Redirect_URL_Label';

export default class SetPasswordPage extends LightningElement {
    token;
    password = '';
    confirmPassword = '';
    message;
    passwordType = 'password';
    showModal = false;
    isValidToken = false;
    isCheckingToken = true;
    isSubmitting = false;

    strengthText = '';
    strengthClass = '';
    ruleLength = '';
    ruleNumber = '';
    ruleUpper = '';
    ruleSpecial = '';

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference && currentPageReference.state && currentPageReference.state.token) {
            this.token = currentPageReference.state.token;
            this.validateToken();
        } else {
            this.isCheckingToken = false;
            this.message = 'Invalid password setup link.';
        }
    }

    get hasMessage() {
        return Boolean(this.message);
    }

    get hasStrengthText() {
        return Boolean(this.strengthText);
    }

    validateToken() {
        this.isCheckingToken = true;

        validateSetPasswordToken({ token: this.token })
            .then((result) => {
                if (result === 'VALID') {
                    this.isValidToken = true;
                    this.message = null;
                } else if (result === 'EXPIRED') {
                    this.isValidToken = false;
                    this.message = 'This link has expired.';
                } else {
                    this.isValidToken = false;
                    this.message = 'You have already set your password or this link is invalid.';
                }
            })
            .catch(() => {
                this.isValidToken = false;
                this.message = 'Error validating link.';
            })
            .finally(() => {
                this.isCheckingToken = false;
            });
    }

    handleChange(event) {
        this.password = event.target.value;
        this.evaluatePassword(this.password);

        if (this.confirmPassword && this.confirmPassword === this.password) {
            this.clearFieldError();
        }
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

    evaluatePassword(passwordValue) {
        let score = 0;

        const hasLength = passwordValue.length >= 6;
        const hasNumber = /\d/.test(passwordValue);
        const hasUpper = /[A-Z]/.test(passwordValue);
        const hasSpecial = /[$%@#!^&*]/.test(passwordValue);

        this.ruleLength = hasLength ? 'valid' : 'invalid';
        this.ruleNumber = hasNumber ? 'valid' : 'invalid';
        this.ruleUpper = hasUpper ? 'valid' : 'invalid';
        this.ruleSpecial = hasSpecial ? 'valid' : 'invalid';

        if (hasLength) {
            score += 1;
        }

        if (hasNumber) {
            score += 1;
        }

        if (hasUpper) {
            score += 1;
        }

        if (hasSpecial) {
            score += 1;
        }

        if (passwordValue.length === 0) {
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
        if (this.isSubmitting) {
            return;
        }

        if (!this.password || !this.confirmPassword) {
            this.setFieldError('Please complete all required fields.');
            return;
        }

        if (this.password !== this.confirmPassword) {
            this.setFieldError('Passwords do not match.');
            return;
        }

        this.clearFieldError();

        const isValidPassword =
            this.password.length >= 6 &&
            /\d/.test(this.password) &&
            /[A-Z]/.test(this.password) &&
            /[$%@#!^&*]/.test(this.password);

        if (!isValidPassword) {
            this.setFieldError('Password must meet all requirements.');
            return;
        }

        this.clearFieldError();
        this.isSubmitting = true;

        setPassword({
            token: this.token,
            newPassword: this.password
        })
            .then(() => {
                this.showModal = true;
                this.message = null;
            })
            .catch((error) => {
                this.message = error && error.body && error.body.message
                    ? error.body.message
                    : 'Error setting password.';
            })
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    closeModal() {
        this.showModal = false;
        this.password = '';
        this.confirmPassword = '';

        const redirectUrl = (AreliaSiteRedirectUrlLabel || '').trim();

        if (redirectUrl) {
            window.location.assign(redirectUrl);
        }
    }
}