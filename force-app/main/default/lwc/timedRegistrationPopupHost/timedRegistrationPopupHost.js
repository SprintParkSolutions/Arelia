import { LightningElement, track } from 'lwc';

const FIRST_DELAY_MS = 2 * 60 * 1000;   // 1 minute
const SECOND_DELAY_MS = 8 * 60 * 1000;  // 5 minutes from page load
const REPEAT_DELAY_MS = 10 * 60 * 1000;  // every 3 minutes after that

export default class TimedRegistrationPopupHost extends LightningElement {
    @track showPopup = false;

    visitStartTime;
    popupCount = 0;

    openTimer;

    connectedCallback() {
        this.visitStartTime = Date.now();
        this.scheduleNextPopup();
    }

    disconnectedCallback() {
        this.clearAllTimers();
    }

    scheduleNextPopup() {
        this.clearOpenTimer();

        let delay;

        if (this.popupCount === 0) {
            delay = FIRST_DELAY_MS;
        } else if (this.popupCount === 1) {
            const elapsed = Date.now() - this.visitStartTime;
            delay = Math.max(0, SECOND_DELAY_MS - elapsed);
        } else {
            delay = REPEAT_DELAY_MS;
        }

        this.openTimer = window.setTimeout(() => {
            this.openPopup();
        }, delay);
    }

    openPopup() {
        this.showPopup = true;
        this.popupCount += 1;
    }

    handlePopupClose() {
        this.closePopupAndReschedule();
    }

    closePopupAndReschedule() {
        this.showPopup = false;
        this.scheduleNextPopup();
    }

    clearOpenTimer() {
        if (this.openTimer) {
            clearTimeout(this.openTimer);
            this.openTimer = null;
        }
    }

    clearAllTimers() {
        this.clearOpenTimer();
    }
}