import { createElement } from '@lwc/engine-dom';
import CaseTrackingModule from 'c/caseTrackingModule';
import requestTrackingOtp from '@salesforce/apex/CaseTrackingController.requestTrackingOtp';
import verifyTrackingOtp from '@salesforce/apex/CaseTrackingController.verifyTrackingOtp';

jest.mock(
    '@salesforce/apex/CaseTrackingController.requestTrackingOtp',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/CaseTrackingController.verifyTrackingOtp',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

const flushPromises = () => new Promise(setImmediate);

describe('c-case-tracking-module', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.clearAllTimers();
    });

    it('requests OTP and moves to verify step', async () => {
        requestTrackingOtp.mockResolvedValue({
            success: true,
            message: 'OTP sent',
            maskedEmail: 'p***l@e***e.com',
            resendAvailableInSeconds: 45
        });

        const element = createElement('c-case-tracking-module', {
            is: CaseTrackingModule
        });
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('.lookup-input');
        input.value = '00001042';
        input.dispatchEvent(new CustomEvent('input'));

        const sendButton = element.shadowRoot.querySelector('.primary-btn');
        sendButton.click();

        await flushPromises();

        expect(requestTrackingOtp).toHaveBeenCalledTimes(1);
        expect(requestTrackingOtp.mock.calls[0][0]).toEqual({ caseReference: '00001042' });
        expect(element.shadowRoot.textContent).toContain('Email Verification');
    });

    it('verifies OTP and renders tracking result cards', async () => {
        requestTrackingOtp.mockResolvedValue({
            success: true,
            message: 'OTP sent',
            maskedEmail: 'p***l@e***e.com',
            resendAvailableInSeconds: 45
        });

        verifyTrackingOtp.mockResolvedValue({
            success: true,
            tracking: {
                caseId: '500000000000001AAA',
                caseNumber: '00001042',
                subject: 'Laptop display issue',
                status: 'Working',
                priority: 'Medium',
                createdDate: '2026-04-09T10:00:00.000Z',
                lastUpdatedDate: '2026-04-09T11:00:00.000Z',
                stages: [
                    {
                        key: 'stage-0',
                        label: 'Case Received',
                        description: 'Created',
                        completed: true,
                        current: false,
                        timestamp: '2026-04-09T10:00:00.000Z'
                    },
                    {
                        key: 'stage-1',
                        label: 'Verification and Triage',
                        description: 'Assigned',
                        completed: false,
                        current: true,
                        timestamp: '2026-04-09T11:00:00.000Z'
                    }
                ],
                updates: [
                    {
                        key: 'update-1',
                        title: 'Current Status: Working',
                        message: 'Support team is investigating.',
                        tone: 'info',
                        timestamp: '2026-04-09T11:00:00.000Z'
                    }
                ]
            }
        });

        const element = createElement('c-case-tracking-module', {
            is: CaseTrackingModule
        });
        document.body.appendChild(element);

        const caseInput = element.shadowRoot.querySelector('.lookup-input');
        caseInput.value = '00001042';
        caseInput.dispatchEvent(new CustomEvent('input'));

        element.shadowRoot.querySelector('.primary-btn').click();
        await flushPromises();

        const otpInput = element.shadowRoot.querySelector('.otp-input');
        otpInput.value = '654321';
        otpInput.dispatchEvent(new CustomEvent('input'));

        const primaryButtons = element.shadowRoot.querySelectorAll('.primary-btn');
        primaryButtons[1].click();
        await flushPromises();

        expect(verifyTrackingOtp).toHaveBeenCalledTimes(1);
        expect(verifyTrackingOtp.mock.calls[0][0]).toEqual({
            caseReference: '00001042',
            otpCode: '654321'
        });

        expect(element.shadowRoot.textContent).toContain('Case Summary');
        expect(element.shadowRoot.textContent).toContain('00001042');
        expect(element.shadowRoot.textContent).toContain('Progress Pipeline');
    });
});
