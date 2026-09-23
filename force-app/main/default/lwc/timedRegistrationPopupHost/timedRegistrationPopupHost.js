import { LightningElement, track } from 'lwc';

const FIRST_DELAY_MS = 2 * 60 * 1000;      // first popup after 2 minutes
const REPEAT_DELAY_MS = 6 * 60 * 1000;     // next popup every 6 minutes from previous open
const AUTO_CLOSE_MS = 5 * 60 * 1000;       // popup auto closes after 5 minutes

export default class TimedRegistrationPopupHost extends LightningElement {
    @track showPopup = false;

    firstOpenTimer;
    nextOpenTimer;
    autoCloseTimer;

    connectedCallback() {
        this.startPopupFlow();
    }

    disconnectedCallback() {
        this.clearAllTimers();
    }

    startPopupFlow() {
        this.clearAllTimers();

        this.firstOpenTimer = window.setTimeout(() => {
            this.openPopupAndContinueCycle();
        }, FIRST_DELAY_MS);
    }

    openPopupAndContinueCycle() {
        this.clearAutoCloseTimer();
        this.clearNextOpenTimer();

        this.showPopup = true;

        // Auto close after 5 minutes
        this.autoCloseTimer = window.setTimeout(() => {
            this.showPopup = false;
        }, AUTO_CLOSE_MS);

        // Open next popup 6 minutes after this popup opened
        this.nextOpenTimer = window.setTimeout(() => {
            this.openPopupAndContinueCycle();
        }, REPEAT_DELAY_MS);
    }

    handlePopupClose() {
        // Manual close only closes current popup.
        // Next popup will still come based on 6-minute cycle.
        this.showPopup = false;
    }

    clearAutoCloseTimer() {
        if (this.autoCloseTimer) {
            clearTimeout(this.autoCloseTimer);
            this.autoCloseTimer = null;
        }
    }

    clearNextOpenTimer() {
        if (this.nextOpenTimer) {
            clearTimeout(this.nextOpenTimer);
            this.nextOpenTimer = null;
        }
    }

    clearFirstOpenTimer() {
        if (this.firstOpenTimer) {
            clearTimeout(this.firstOpenTimer);
            this.firstOpenTimer = null;
        }
    }

    clearAllTimers() {
        this.clearFirstOpenTimer();
        this.clearNextOpenTimer();
        this.clearAutoCloseTimer();
    }
}