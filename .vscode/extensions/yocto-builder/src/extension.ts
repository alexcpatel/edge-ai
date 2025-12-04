import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import { exec } from 'child_process';

// Wrapper for execAsync with timeout to prevent hanging processes
async function execWithTimeout(command: string, options: { cwd?: string; timeout?: number } = {}): Promise<{ stdout: string; stderr: string }> {
    const timeout = options.timeout || 30000; // Default 30 second timeout
    const { cwd } = options;

    return new Promise((resolve, reject) => {
        let killedByTimeout = false;
        let resolved = false;

        const child = exec(command, { cwd }, (error, stdout, stderr) => {
            if (resolved) return; // Already handled by timeout
            resolved = true;
            clearTimeout(timeoutId);

            if (error) {
                // If process was killed due to timeout, reject with timeout error
                if (killedByTimeout) {
                    reject(new Error(`Command timed out after ${timeout}ms: ${command}`));
                } else {
                    reject(error);
                }
            } else {
                resolve({ stdout, stderr });
            }
        });

        const timeoutId = setTimeout(() => {
            if (resolved) return; // Process already completed
            killedByTimeout = true;
            resolved = true;

            // Kill the process tree to prevent zombie processes
            if (child.pid) {
                try {
                    // On Unix systems, kill the process group
                    process.kill(-child.pid, 'SIGTERM');
                } catch (e) {
                    // Fallback to killing just the process
                    try {
                        child.kill('SIGTERM');
                    } catch (killError) {
                        // Process may have already exited
                    }
                }
            }
            reject(new Error(`Command timed out after ${timeout}ms: ${command}`));
        }, timeout);
    });
}

interface InstanceStatus {
    id: string;
    type: string;
    state: string;
    ip?: string;
    healthy?: boolean;
}

interface BuildStatus {
    running: boolean;
    elapsed?: string;
    elapsedSeconds?: number; // Total seconds for client-side incrementing
    taskProgress?: {
        current: number;
        total: number;
    };
    lastSuccessfulBuild?: string;
}

interface ControllerStatus {
    name: string;
    host: string;
    reachable: boolean;
}

interface FlashStatus {
    running: boolean;
    elapsed?: string;
    elapsedSeconds?: number; // Total seconds for client-side incrementing
}

interface CostRun {
    start: number;      // Unix timestamp
    end: number;        // Unix timestamp
    duration_secs: number;
    cost: number;
    instance_type: string;
}

interface CostData {
    runs: CostRun[];
    total_duration_secs: number;
    total_cost: number;
    hourly_rate: number;
    error?: string;
}

type WorkflowPhase = 'idle' | 'build' | 'flash' | 'complete';

interface WorkflowState {
    phase: WorkflowPhase;
    startTime?: number;
    buildStartTime?: number;
    buildEndTime?: number;
    buildFailed?: boolean;
    flashStartTime?: number;
    flashEndTime?: number;
    flashFailed?: boolean;
}

interface PreviousRunTimes {
    build?: number;   // Duration in ms
    flash?: number;
    total?: number;
}

export function activate(context: vscode.ExtensionContext) {
    const outputChannel = vscode.window.createOutputChannel('Yocto Builder');
    outputChannel.appendLine('Yocto Builder extension activated');
    outputChannel.show();

    let provider: YoctoBuilderProvider | undefined;

    try {
        provider = new YoctoBuilderProvider(context.extensionPath);
        const treeView = vscode.window.createTreeView('yocto-builder', {
            treeDataProvider: provider,
            showCollapseAll: false
        });

        // Register commands first
        context.subscriptions.push(
            vscode.commands.registerCommand('yocto-builder.showPanel', () => {
                outputChannel.appendLine('Command: showPanel');
                YoctoBuilderPanel.createOrShow(context.extensionPath, context);
            }),
            vscode.commands.registerCommand('yocto-builder.instanceStart', () => {
                outputChannel.appendLine('Command: instanceStart');
                runCommand('make firmware-ec2-start');
            }),
            vscode.commands.registerCommand('yocto-builder.instanceStop', () => {
                outputChannel.appendLine('Command: instanceStop');
                runCommand('make firmware-ec2-stop');
            }),
            vscode.commands.registerCommand('yocto-builder.instanceSsh', () => {
                outputChannel.appendLine('Command: instanceSsh');
                runCommand('make firmware-ec2-ssh', 'Yocto Builder - SSH');
            }),
            vscode.commands.registerCommand('yocto-builder.instanceHealth', () => {
                outputChannel.appendLine('Command: instanceHealth');
                runCommand('make firmware-ec2-health', 'Yocto Builder - Health');
            }),
            vscode.commands.registerCommand('yocto-builder.buildStart', () => {
                outputChannel.appendLine('Command: buildStart');
                runCommand('make firmware-build', 'Yocto Builder - Build');
            }),
            vscode.commands.registerCommand('yocto-builder.buildWatch', () => {
                outputChannel.appendLine('Command: buildWatch');
                runCommand('make firmware-build-watch', 'Yocto Builder - Watch');
            }),
            vscode.commands.registerCommand('yocto-builder.buildTerminate', () => {
                outputChannel.appendLine('Command: buildTerminate');
                runCommand('make firmware-build-terminate', 'Yocto Builder - Terminate');
            }),
            vscode.commands.registerCommand('yocto-builder.recoveryEnable', () => {
                outputChannel.appendLine('Command: recoveryEnable');
                runCommand('make firmware-recovery-enable', 'Yocto Builder - Recovery');
            }),
            vscode.commands.registerCommand('yocto-builder.flashStart', () => {
                outputChannel.appendLine('Command: flashStart');
                runCommand('make firmware-flash', 'Yocto Builder - Flash');
            }),
            vscode.commands.registerCommand('yocto-builder.flashWatch', () => {
                outputChannel.appendLine('Command: flashWatch');
                runCommand('make firmware-flash-watch', 'Yocto Builder - Flash');
            }),
            vscode.commands.registerCommand('yocto-builder.flashTerminate', () => {
                outputChannel.appendLine('Command: flashTerminate');
                runCommand('make firmware-flash-terminate', 'Yocto Builder - Flash');
            }),
            vscode.commands.registerCommand('yocto-builder.buildFlash', () => {
                outputChannel.appendLine('Command: buildFlash');
                runCommand('make firmware-build-flash', 'Yocto Builder - Build & Flash');
            }),
            vscode.commands.registerCommand('yocto-builder.refresh', () => {
                outputChannel.appendLine('Command: refresh');
                provider?.refresh();
                YoctoBuilderPanel.currentPanel?.update();
            })
        );

        outputChannel.appendLine('Commands registered');

        // Auto-open panel on activation (only if workspace is available)
        if (vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders.length > 0) {
            outputChannel.appendLine('Workspace found, opening panel');
            YoctoBuilderPanel.createOrShow(context.extensionPath, context);
        } else {
            outputChannel.appendLine('No workspace found');
            // Show message to open workspace
            vscode.window.showInformationMessage(
                'Yocto Builder: Please open a workspace folder to use this extension',
                'Open Folder'
            ).then(selection => {
                if (selection === 'Open Folder') {
                    vscode.commands.executeCommand('workbench.action.files.openFolder');
                }
            });
        }
    } catch (error) {
        outputChannel.appendLine(`Error during activation: ${error}`);
        vscode.window.showErrorMessage(`Yocto Builder activation error: ${error}`);
    }

    // Auto-refresh every 5 seconds with debouncing to prevent overlapping calls
    let refreshInProgress = false;
    const refreshInterval = setInterval(() => {
        if (!refreshInProgress) {
            refreshInProgress = true;
            provider?.refresh();
            YoctoBuilderPanel.currentPanel?.update().finally(() => {
                refreshInProgress = false;
            });
        }
    }, 15000);

    context.subscriptions.push({
        dispose: () => clearInterval(refreshInterval)
    });
}

// Cache terminals by name to reuse them instead of creating new ones
const terminalCache = new Map<string, vscode.Terminal>();

function runCommand(command: string, terminalName?: string): void {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) {
        vscode.window.showErrorMessage('No workspace folder found');
        return;
    }

    const name = terminalName || 'Yocto Builder';

    // Reuse existing terminal if available and not disposed
    let terminal = terminalCache.get(name);
    if (!terminal || terminal.exitStatus !== undefined) {
        terminal = vscode.window.createTerminal(name);
        terminalCache.set(name, terminal);

        // Clean up terminal from cache when it's disposed
        vscode.window.onDidCloseTerminal((closedTerminal) => {
            if (closedTerminal === terminal) {
                terminalCache.delete(name);
            }
        });
    }

    terminal.show(true); // Show and focus the terminal
    terminal.sendText(`cd ${workspaceFolder.uri.fsPath} && ${command}`);
}

class YoctoBuilderProvider implements vscode.TreeDataProvider<vscode.TreeItem> {
    private _onDidChangeTreeData: vscode.EventEmitter<vscode.TreeItem | undefined | null | void> = new vscode.EventEmitter<vscode.TreeItem | undefined | null | void>();
    readonly onDidChangeTreeData: vscode.Event<vscode.TreeItem | undefined | null | void> = this._onDidChangeTreeData.event;

    constructor(private extensionPath: string) { }

    refresh(): void {
        this._onDidChangeTreeData.fire();
    }

    getTreeItem(element: vscode.TreeItem): vscode.TreeItem {
        return element;
    }

    async getChildren(element?: vscode.TreeItem): Promise<vscode.TreeItem[]> {
        if (!element) {
            return [
                new StatusItem('EC2 Status', 'ec2-status'),
                new StatusItem('Build Status', 'build-status')
            ];
        }
        return [];
    }
}

class StatusItem extends vscode.TreeItem {
    constructor(
        public readonly label: string,
        public readonly type: string
    ) {
        super(label, vscode.TreeItemCollapsibleState.None);
        this.command = {
            command: 'yocto-builder.showPanel',
            title: 'Show Status'
        };
    }
}

class YoctoBuilderPanel {
    public static currentPanel: YoctoBuilderPanel | undefined;
    private readonly _panel: vscode.WebviewPanel;
    private readonly _extensionPath: string;
    private readonly _context: vscode.ExtensionContext;
    private _disposables: vscode.Disposable[] = [];
    private _previousBuildRunning: boolean = false;

    // Workflow state tracking (persists across updates)
    private static _workflowState: WorkflowState = { phase: 'idle' };

    // Previous run times for estimates
    private static _previousRunTimes: PreviousRunTimes = {};

    public static createOrShow(extensionPath: string, context: vscode.ExtensionContext) {
        const column = vscode.window.activeTextEditor
            ? vscode.window.activeTextEditor.viewColumn
            : undefined;

        if (YoctoBuilderPanel.currentPanel) {
            YoctoBuilderPanel.currentPanel._panel.reveal(column);
            return;
        }

        const panel = vscode.window.createWebviewPanel(
            'yoctoBuilder',
            'Yocto Builder',
            column || vscode.ViewColumn.One,
            {
                enableScripts: true,
                localResourceRoots: [vscode.Uri.file(path.join(extensionPath, 'media'))]
            }
        );

        YoctoBuilderPanel.currentPanel = new YoctoBuilderPanel(panel, extensionPath, context);
    }

    private constructor(panel: vscode.WebviewPanel, extensionPath: string, context: vscode.ExtensionContext) {
        this._panel = panel;
        this._extensionPath = extensionPath;
        this._context = context;

        // Load previous run times from global state
        YoctoBuilderPanel._previousRunTimes = context.globalState.get('workflowPreviousRunTimes', {});

        this._panel.onDidDispose(() => this.dispose(), null, this._disposables);
        this._panel.webview.onDidReceiveMessage(
            async message => {
                switch (message.command) {
                    case 'instanceStart':
                        runCommand('make firmware-ec2-start', 'Yocto Builder');
                        break;
                    case 'instanceStop':
                        await this.handleInstanceStop();
                        break;
                    case 'instanceSsh':
                        runCommand('make firmware-ec2-ssh', 'Yocto Builder - SSH');
                        break;
                    case 'instanceHealth':
                        runCommand('make firmware-ec2-health', 'Yocto Builder - Health');
                        break;
                    case 'buildStart':
                        runCommand('make firmware-build', 'Yocto Builder - Build');
                        break;
                    case 'buildWatch':
                        runCommand('make firmware-build-watch', 'Yocto Builder - Build');
                        break;
                    case 'buildTerminate':
                        runCommand('make firmware-build-terminate', 'Yocto Builder');
                        break;
                    case 'recoveryEnable':
                        runCommand('make firmware-recovery-enable', 'Yocto Builder - Recovery');
                        break;
                    case 'flashStart':
                        const flashMode = message.mode || 'bootloader';
                        runCommand(`make firmware-flash MODE=${flashMode}`, 'Yocto Builder - Flash');
                        break;
                    case 'toggleFlashMode':
                        this._context.globalState.update('flashMode', message.value || 'bootloader');
                        this.update();
                        break;
                    case 'flashWatch':
                        runCommand('make firmware-flash-watch', 'Yocto Builder - Flash');
                        break;
                    case 'flashTerminate':
                        runCommand('make firmware-flash-terminate', 'Yocto Builder - Flash');
                        break;
                    case 'buildFlash':
                        this.runBuildFlashWorkflow();
                        break;
                    case 'refresh':
                        this.update();
                        break;
                }
            },
            null,
            this._disposables
        );

        this.update();
    }

    public async update() {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (workspaceFolder) {
            // Track build state for UI updates
            const buildStatus = await this.getBuildStatus(workspaceFolder.uri.fsPath);
            const flashStatus = await this.getFlashStatus(workspaceFolder.uri.fsPath);
            const instanceStatus = await this.getInstanceStatus(workspaceFolder.uri.fsPath);

            this._previousBuildRunning = buildStatus.running;
        }

        const webview = this._panel.webview;
        this._panel.webview.html = await this._getHtmlForWebview(webview);
    }

    private async runBuildFlashWorkflow() {
        const now = Date.now();
        YoctoBuilderPanel._workflowState = {
            phase: 'build',
            startTime: now,
            buildStartTime: now
        };
        this.update();

        // Run build
        const buildSuccess = await this.runCommandAsync('make firmware-build', 'Yocto Builder - Build');

        const state = YoctoBuilderPanel._workflowState;
        state.buildEndTime = Date.now();

        if (!buildSuccess) {
            state.buildFailed = true;
            state.phase = 'idle';
            this.update();
            return;
        }

        // Run flash
        state.phase = 'flash';
        state.flashStartTime = Date.now();
        this.update();

        const flashSuccess = await this.runCommandAsync('make firmware-flash', 'Yocto Builder - Flash');

        state.flashEndTime = Date.now();
        state.flashFailed = !flashSuccess;
        state.phase = flashSuccess ? 'complete' : 'idle';

        // Save run times for future estimates
        this.saveRunTimes();
        this.update();
    }

    private runCommandAsync(command: string, terminalName: string): Promise<boolean> {
        return new Promise((resolve) => {
            const terminal = vscode.window.createTerminal(terminalName);
            terminal.show();
            terminal.sendText(`${command}; exit $?`);

            const disposable = vscode.window.onDidCloseTerminal(closedTerminal => {
                if (closedTerminal === terminal) {
                    disposable.dispose();
                    // exitStatus is undefined if user closes terminal, treat as failure
                    resolve(closedTerminal.exitStatus?.code === 0);
                }
            });
        });
    }

    private saveRunTimes() {
        const state = YoctoBuilderPanel._workflowState;
        const buildDuration = state.buildStartTime && state.buildEndTime
            ? state.buildEndTime - state.buildStartTime : undefined;
        const flashDuration = state.flashStartTime && state.flashEndTime
            ? state.flashEndTime - state.flashStartTime : undefined;
        const totalDuration = state.startTime ? Date.now() - state.startTime : undefined;

        YoctoBuilderPanel._previousRunTimes = {
            build: buildDuration,
            flash: flashDuration,
            total: totalDuration
        };
        this._context.globalState.update('workflowPreviousRunTimes', YoctoBuilderPanel._previousRunTimes);
    }

    public static resetWorkflow() {
        YoctoBuilderPanel._workflowState = { phase: 'idle' };
    }

    private formatDurationCompact(ms: number): string {
        const secs = Math.floor(ms / 1000);
        if (secs < 60) return `${secs}s`;
        const mins = Math.floor(secs / 60);
        if (mins < 60) {
            const remainSecs = secs % 60;
            return remainSecs > 0 ? `${mins}m${remainSecs}s` : `${mins}m`;
        }
        const hours = Math.floor(mins / 60);
        const remainMins = mins % 60;
        return remainMins > 0 ? `${hours}h${remainMins}m` : `${hours}h`;
    }

    private async handleInstanceStop(): Promise<void> {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (!workspaceFolder) {
            vscode.window.showErrorMessage('No workspace folder found');
            return;
        }

        // Show confirmation dialog immediately (before checking build status)
        const confirm = await vscode.window.showWarningMessage(
            'Are you sure you want to stop the instance?',
            { modal: true },
            'Yes, Stop Instance',
            'Cancel'
        );

        if (confirm !== 'Yes, Stop Instance') {
            return;
        }

        // Check if build is running (after confirmation for faster UX)
        try {
            const buildStatus = await this.getBuildStatus(workspaceFolder.uri.fsPath);
            if (buildStatus.running) {
                const result = await vscode.window.showWarningMessage(
                    'A build is currently running. You must terminate the build before stopping the instance.',
                    'Terminate Build',
                    'Cancel'
                );
                if (result === 'Terminate Build') {
                    runCommand('make firmware-build-terminate');
                    // Wait a moment and check again
                    await new Promise(resolve => setTimeout(resolve, 2000));
                    const newBuildStatus = await this.getBuildStatus(workspaceFolder.uri.fsPath);
                    if (newBuildStatus.running) {
                        vscode.window.showErrorMessage('Build termination may still be in progress. Please wait and try again.');
                        return;
                    }
                } else {
                    return;
                }
            }
        } catch (error) {
            // If we can't check build status, continue
        }

        // Stop the instance
        runCommand('make firmware-ec2-stop');
    }

    private async _getHtmlForWebview(webview: vscode.Webview): Promise<string> {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (!workspaceFolder) {
            return `<!DOCTYPE html>
<html>
<head><title>Yocto Builder</title></head>
<body style="padding: 20px; font-family: var(--vscode-font-family);">
    <h2>No Workspace Folder Found</h2>
    <p>Please open the workspace folder (edge-ai) in this window to use the Yocto Builder extension.</p>
    <p>Go to File > Open Folder and select the edge-ai directory.</p>
</body>
</html>`;
        }

        // Run status checks in parallel to reduce delay
        const [instanceStatus, buildStatus, controllerStatus, flashStatus, costData] = await Promise.all([
            this.getInstanceStatus(workspaceFolder.uri.fsPath),
            this.getBuildStatus(workspaceFolder.uri.fsPath),
            this.getControllerStatus(workspaceFolder.uri.fsPath),
            this.getFlashStatus(workspaceFolder.uri.fsPath),
            this.getCostData(workspaceFolder.uri.fsPath)
        ]);

        // Read HTML template
        const htmlPath = path.join(this._extensionPath, 'media', 'webview.html');
        let html = fs.readFileSync(htmlPath, 'utf8');

        // Normalize instance state for comparison
        const instanceRunning = instanceStatus.state?.toLowerCase() === 'running';

        // Replace template variables
        html = html.replace(/\{\{INSTANCE_STATUS_CLASS\}\}/g, instanceRunning ? 'running' : 'stopped');
        html = html.replace(/\{\{INSTANCE_STATE\}\}/g, instanceStatus.state || 'unknown');
        html = html.replace(/\{\{INSTANCE_ID\}\}/g, instanceStatus.id || 'N/A');
        html = html.replace(/\{\{INSTANCE_TYPE\}\}/g, instanceStatus.type || 'N/A');
        html = html.replace(/\{\{INSTANCE_IP\}\}/g, instanceStatus.ip || 'N/A');
        html = html.replace(/\{\{INSTANCE_START_DISABLED\}\}/g, instanceRunning ? 'disabled' : '');
        // Disable stop if instance is not running OR if build is running
        html = html.replace(/\{\{INSTANCE_STOP_DISABLED\}\}/g, (!instanceRunning || buildStatus.running) ? 'disabled' : '');
        // Disable SSH and Health if instance is not running
        html = html.replace(/\{\{INSTANCE_SSH_DISABLED\}\}/g, !instanceRunning ? 'disabled' : '');
        html = html.replace(/\{\{INSTANCE_HEALTH_DISABLED\}\}/g, !instanceRunning ? 'disabled' : '');

        // Cost history section
        let costHtml = '';
        if (costData.runs && costData.runs.length > 0) {
            costHtml = `
            <div style="margin-top: 10px; padding-top: 8px; border-top: 1px solid var(--vscode-panel-border);">
                <div style="font-size: 10px; color: var(--vscode-descriptionForeground); margin-bottom: 4px;">
                    Last ${costData.runs.length} runs · $${costData.hourly_rate}/hr
                </div>
                <table style="width: 100%; font-size: 10px; border-collapse: collapse;">
                    <tr style="color: var(--vscode-descriptionForeground);">
                        <td>When</td><td style="text-align:right">Duration</td><td style="text-align:right">Cost</td>
                    </tr>
                    ${costData.runs.slice().reverse().map(r => {
                        const costStr = r.cost < 0.01 ? r.cost.toFixed(3) : r.cost.toFixed(2);
                        return `<tr>
                        <td>${this.formatRelativeTime(r.start)}</td><td style="text-align:right">${this.formatDurationShort(r.duration_secs)}</td><td style="text-align:right">$${costStr}</td>
                    </tr>`;
                    }).join('')}
                </table>
            </div>`;
        } else if (!costData.error) {
            costHtml = `<div style="margin-top: 8px; font-size: 10px; color: var(--vscode-descriptionForeground);">No usage history yet</div>`;
        }
        html = html.replace(/\{\{COST_HISTORY\}\}/g, costHtml);

        html = html.replace(/\{\{BUILD_STATUS_CLASS\}\}/g, buildStatus.running ? 'running' : 'stopped');
        html = html.replace(/\{\{BUILD_STATUS_TEXT\}\}/g, buildStatus.running ? 'Running' : 'Not Running');
        // Disable Start Build only if build is already running (instance will auto-start via Makefile)
        html = html.replace(/\{\{BUILD_START_DISABLED\}\}/g, buildStatus.running ? 'disabled' : '');
        // Disable Watch/Terminate if build is not running
        html = html.replace(/\{\{BUILD_WATCH_DISABLED\}\}/g, !buildStatus.running ? 'disabled' : '');
        html = html.replace(/\{\{BUILD_TERMINATE_DISABLED\}\}/g, !buildStatus.running ? 'disabled' : '');

        // Build workflow note (EC2 auto-stops after build)
        html = html.replace(/\{\{STOP_ON_COMPLETE\}\}/g, '');

        // Download artifacts button - removed
        html = html.replace(/\{\{DOWNLOAD_ARTIFACTS_BUTTON\}\}/g, '');

        // Build elapsed time section - pass elapsed seconds for client-side incrementing
        const elapsedHtml = buildStatus.elapsed ? `
        <div class="info-row">
            <span class="info-label">Elapsed:</span>
            <span id="elapsedTime" data-elapsed-seconds="${buildStatus.elapsedSeconds || 0}" data-is-running="${buildStatus.running}">${buildStatus.elapsed}</span>
        </div>
        ` : '';
        html = html.replace(/\{\{BUILD_ELAPSED_TIME\}\}/g, elapsedHtml);

        // Build task progress section
        let taskProgressHtml = '';
        if (buildStatus.taskProgress && buildStatus.taskProgress.total > 0) {
            const percentage = (buildStatus.taskProgress.current / buildStatus.taskProgress.total) * 100;
            const percentageStr = percentage.toFixed(1);
            taskProgressHtml = `<div class="info-row">
            <span class="info-label">Progress:</span>
            <span>${buildStatus.taskProgress.current} / ${buildStatus.taskProgress.total} tasks</span>
        </div>
        <div class="progress-bar-container">
            <div class="progress-bar-wrapper">
                <div class="progress-bar-fg" style="width: ${percentageStr}%"></div>
            </div>
            <span class="progress-percentage">${percentageStr}%</span>
        </div>`;
        }
        html = html.replace(/\{\{BUILD_TASK_PROGRESS\}\}/g, taskProgressHtml);

        // Last successful build section
        const lastBuildHtml = buildStatus.lastSuccessfulBuild ? `
        <div class="info-row">
            <span class="info-label">Last successful:</span>
            <span>${this.escapeHtml(buildStatus.lastSuccessfulBuild)}</span>
        </div>
        ` : '';
        html = html.replace(/\{\{BUILD_LAST_SUCCESSFUL\}\}/g, lastBuildHtml);

        // Controller status section
        html = html.replace(/\{\{CONTROLLER_STATUS_CLASS\}\}/g, controllerStatus.reachable ? 'running' : 'stopped');
        html = html.replace(/\{\{CONTROLLER_NAME\}\}/g, this.escapeHtml(controllerStatus.name || 'N/A'));
        html = html.replace(/\{\{CONTROLLER_HOST\}\}/g, this.escapeHtml(controllerStatus.host || 'N/A'));
        html = html.replace(/\{\{CONTROLLER_STATUS_TEXT\}\}/g, controllerStatus.reachable ? 'Reachable' : 'Unreachable');

        // Flash status section
        html = html.replace(/\{\{FLASH_STATUS_CLASS\}\}/g, flashStatus.running ? 'running' : 'stopped');
        html = html.replace(/\{\{FLASH_STATUS_TEXT\}\}/g, flashStatus.running ? 'Running' : 'Not Running');
        // Flash pulls from S3 and handles recovery mode internally - just need controller reachable
        const flashStartDisabled = flashStatus.running || !controllerStatus.reachable;
        html = html.replace(/\{\{FLASH_START_DISABLED\}\}/g, flashStartDisabled ? 'disabled' : '');
        html = html.replace(/\{\{FLASH_DISABLED_REASON\}\}/g, '');
        html = html.replace(/\{\{FLASH_WATCH_DISABLED\}\}/g, !flashStatus.running ? 'disabled' : '');
        html = html.replace(/\{\{FLASH_TERMINATE_DISABLED\}\}/g, !flashStatus.running ? 'disabled' : '');

        // Flash elapsed time section
        const flashElapsedHtml = flashStatus.running ? `
        <div class="info-row">
            <span class="info-label">Elapsed:</span>
            <span id="flashElapsedTime" data-elapsed-seconds="${flashStatus.elapsedSeconds || 0}" data-is-running="${flashStatus.running}">${flashStatus.elapsed || '00:00'}</span>
        </div>
        ` : '';
        html = html.replace(/\{\{FLASH_ELAPSED_TIME\}\}/g, flashElapsedHtml);

        // Flash device status section - removed (flash command handles recovery mode internally)
        html = html.replace(/\{\{FLASH_DEVICE_STATUS\}\}/g, '');

        // Flash mode toggle (bootloader vs rootfs)
        const flashMode = this._context.globalState.get<string>('flashMode', 'bootloader');
        const workflowActive = YoctoBuilderPanel._workflowState.phase !== 'idle' && YoctoBuilderPanel._workflowState.phase !== 'complete';
        const flashModeDisabled = flashStatus.running || workflowActive;
        const flashModeHtml = `
        <div class="stop-on-complete" style="margin-top: 8px;">
            <label style="display: block; margin-bottom: 4px; font-weight: bold;">Flash Target:</label>
            <label style="display: flex; align-items: center; gap: 6px; cursor: ${flashModeDisabled ? 'not-allowed' : 'pointer'}; opacity: ${flashModeDisabled ? '0.5' : '1'};">
                <input type="radio" name="flashMode" value="bootloader" ${flashMode === 'bootloader' ? 'checked' : ''} ${flashModeDisabled ? 'disabled' : ''}
                    onchange="updateFlashMode('bootloader')">
                Bootloader (SPI)
            </label>
            <label style="display: flex; align-items: center; gap: 6px; cursor: ${flashModeDisabled ? 'not-allowed' : 'pointer'}; opacity: ${flashModeDisabled ? '0.5' : '1'};">
                <input type="radio" name="flashMode" value="rootfs" ${flashMode === 'rootfs' ? 'checked' : ''} ${flashModeDisabled ? 'disabled' : ''}
                    onchange="updateFlashMode('rootfs')">
                Rootfs (NVMe)
            </label>
        </div>
        `;
        html = html.replace(/\{\{FLASH_MODE_TOGGLE\}\}/g, flashModeHtml);

        // Bottom bar - Build & Flash workflow
        const workflowState = YoctoBuilderPanel._workflowState;
        const workflowRunning = workflowState.phase === 'build' || workflowState.phase === 'flash';
        const workflowDisabled = workflowRunning || !controllerStatus.reachable;
        html = html.replace(/\{\{BUILD_FLASH_DISABLED\}\}/g, workflowDisabled ? 'disabled' : '');

        // Generate progress bar HTML
        const progressHtml = this.getWorkflowProgressHtml();
        html = html.replace(/\{\{WORKFLOW_PROGRESS\}\}/g, progressHtml);

        return html;
    }

    private getWorkflowProgressHtml(): string {
        const state = YoctoBuilderPanel._workflowState;
        const prev = YoctoBuilderPanel._previousRunTimes;
        const now = Date.now();

        // Calculate states
        const buildComplete = state.buildEndTime !== undefined;
        const buildActive = state.phase === 'build';
        const flashComplete = state.flashEndTime !== undefined;
        const flashActive = state.phase === 'flash';
        const isComplete = state.phase === 'complete';
        const isIdle = state.phase === 'idle';

        // Calculate elapsed seconds for JS to increment
        let buildElapsed = 0;
        let flashElapsed = 0;

        if (buildActive && state.buildStartTime) {
            buildElapsed = Math.floor((now - state.buildStartTime) / 1000);
        } else if (buildComplete && state.buildStartTime && state.buildEndTime) {
            buildElapsed = Math.floor((state.buildEndTime - state.buildStartTime) / 1000);
        }

        if (flashActive && state.flashStartTime) {
            flashElapsed = Math.floor((now - state.flashStartTime) / 1000);
        } else if (flashComplete && state.flashStartTime && state.flashEndTime) {
            flashElapsed = Math.floor((state.flashEndTime - state.flashStartTime) / 1000);
        }

        // Use endTime when complete, otherwise use now
        const endTime = isComplete && state.flashEndTime ? state.flashEndTime : now;
        const totalElapsed = state.startTime ? Math.floor((endTime - state.startTime) / 1000) : 0;

        // Build segment classes
        const buildClass = state.buildFailed ? 'failed' : buildComplete ? 'complete' : buildActive ? 'active' : '';
        const flashClass = state.flashFailed ? 'failed' : flashComplete ? 'complete' : flashActive ? 'active' : '';

        // Show previous estimate only during active phase
        const buildEstimateMs = buildActive && prev.build ? prev.build : 0;
        const flashEstimateMs = flashActive && prev.flash ? prev.flash : 0;

        if (isIdle && !buildComplete) {
            const lastRun = prev.total ? `Last: ${this.formatDurationCompact(prev.total)}` : '';
            return `<div class="workflow-idle">${lastRun}</div>`;
        }

        // Show last run time on the right during active workflow
        const lastRunHtml = !isComplete && prev.total
            ? `<div class="progress-last">Last: ${this.formatDurationCompact(prev.total)}</div>`
            : '';

        return `
            <div class="workflow-progress" id="workflowProgress"
                data-phase="${state.phase}"
                data-build-elapsed="${buildElapsed}"
                data-flash-elapsed="${flashElapsed}"
                data-total-elapsed="${totalElapsed}"
                data-build-estimate="${buildEstimateMs}"
                data-flash-estimate="${flashEstimateMs}">
                <div class="progress-segment ${buildClass}" id="buildSegment">
                    <span class="segment-label">Build</span>
                    <span class="segment-time" id="buildTime"></span>
                </div>
                <div class="progress-segment ${flashClass}" id="flashSegment">
                    <span class="segment-label">Flash</span>
                    <span class="segment-time" id="flashTime"></span>
                </div>
                ${lastRunHtml}
                <div class="progress-total" id="totalTime" style="display: ${isComplete ? 'block' : 'none'}"></div>
            </div>
        `;
    }

    private escapeHtml(text: string): string {
        return text
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    private parseElapsedTimeToSeconds(elapsed: string): number {
        // Parse formats like:
        // "01:23:45" (HH:MM:SS)
        // "23:45" (MM:SS)
        // "45" (SS)
        // "1-02:03:45" (D-HH:MM:SS)
        const parts = elapsed.trim().split(/[-:]/);

        if (parts.length === 1) {
            // Just seconds
            return parseInt(parts[0], 10) || 0;
        } else if (parts.length === 2) {
            // MM:SS
            const minutes = parseInt(parts[0], 10) || 0;
            const seconds = parseInt(parts[1], 10) || 0;
            return minutes * 60 + seconds;
        } else if (parts.length === 3) {
            // HH:MM:SS
            const hours = parseInt(parts[0], 10) || 0;
            const minutes = parseInt(parts[1], 10) || 0;
            const seconds = parseInt(parts[2], 10) || 0;
            return hours * 3600 + minutes * 60 + seconds;
        } else if (parts.length === 4) {
            // D-HH:MM:SS
            const days = parseInt(parts[0], 10) || 0;
            const hours = parseInt(parts[1], 10) || 0;
            const minutes = parseInt(parts[2], 10) || 0;
            const seconds = parseInt(parts[3], 10) || 0;
            return days * 86400 + hours * 3600 + minutes * 60 + seconds;
        }

        return 0;
    }

    private async getInstanceStatus(workspacePath: string): Promise<InstanceStatus> {
        try {
            const { stdout } = await execWithTimeout('make firmware-ec2-status', { cwd: workspacePath, timeout: 10000 });
            const lines = stdout.split('\n');

            const status: InstanceStatus = {
                id: '',
                type: '',
                state: 'unknown',
                ip: undefined,
                healthy: false
            };

            for (const line of lines) {
                if (line.includes('Instance ID:')) {
                    status.id = line.split('Instance ID:')[1]?.trim() || '';
                } else if (line.includes('Instance Type:')) {
                    status.type = line.split('Instance Type:')[1]?.trim() || '';
                } else if (line.includes('State:')) {
                    status.state = line.split('State:')[1]?.trim().toLowerCase() || 'unknown';
                } else if (line.includes('IP:')) {
                    status.ip = line.split('IP:')[1]?.trim();
                }
            }

            return status;
        } catch (error) {
            return { id: '', type: '', state: 'unknown' };
        }
    }

    private async getBuildStatus(workspacePath: string): Promise<BuildStatus> {
        try {
            const { stdout } = await execWithTimeout('make firmware-build-status', { cwd: workspacePath, timeout: 10000 });
            return this.parseBuildStatusOutput(stdout);
        } catch (error: any) {
            // execWithTimeout throws on non-zero exit codes or timeout, but stdout is still available in the error
            if (error?.stdout) {
                return this.parseBuildStatusOutput(error.stdout);
            }
            // On timeout or other errors, return safe default
            return { running: false };
        }
    }

    private parseBuildStatusOutput(stdout: string): BuildStatus {
        const lines = stdout.split('\n');

        const status: BuildStatus = {
            running: stdout.includes('Build session is running')
        };

        // Extract elapsed time if available (whether running or not)
        const elapsedMatch = stdout.match(/Elapsed: (.+)/);
        if (elapsedMatch) {
            status.elapsed = elapsedMatch[1];
            // Parse elapsed time to seconds for client-side incrementing
            status.elapsedSeconds = this.parseElapsedTimeToSeconds(elapsedMatch[1]);
        }

        // Extract task progress if available
        const taskProgressMatch = stdout.match(/Progress: Running task (\d+) of (\d+)/);
        if (taskProgressMatch) {
            const current = parseInt(taskProgressMatch[1], 10);
            const total = parseInt(taskProgressMatch[2], 10);
            // Only set if both are valid numbers and total > 0
            if (!isNaN(current) && !isNaN(total) && total > 0) {
                status.taskProgress = {
                    current: current,
                    total: total
                };
            }
        }

        // Extract last successful build time if available
        const lastBuildMatch = stdout.match(/Last successful build: (.+)/);
        if (lastBuildMatch) {
            status.lastSuccessfulBuild = lastBuildMatch[1];
        }

        return status;
    }

    private async getControllerStatus(workspacePath: string): Promise<ControllerStatus> {
        try {
            const { stdout } = await execWithTimeout('make firmware-controller-status C=steamdeck', { cwd: workspacePath, timeout: 10000 });
            return this.parseControllerStatusOutput(stdout);
        } catch (error: any) {
            if (error?.stdout) {
                return this.parseControllerStatusOutput(error.stdout);
            }
            return { name: 'steamdeck', host: 'N/A', reachable: false };
        }
    }

    private parseControllerStatusOutput(stdout: string): ControllerStatus {
        const lines = stdout.split('\n');
        const status: ControllerStatus = {
            name: 'steamdeck',
            host: 'N/A',
            reachable: false
        };

        for (const line of lines) {
            if (line.includes('Controller:')) {
                status.name = line.split('Controller:')[1]?.trim() || 'steamdeck';
            } else if (line.includes('Host:')) {
                status.host = line.split('Host:')[1]?.trim() || 'N/A';
            } else if (line.includes('Status: reachable')) {
                status.reachable = true;
            } else if (line.includes('Status: unreachable')) {
                status.reachable = false;
            }
        }

        return status;
    }

    private parseFlashStatusOutput(stdout: string): FlashStatus {
        const status: FlashStatus = {
            running: stdout.includes('Flash session is running')
        };

        // Extract elapsed time if available
        const elapsedMatch = stdout.match(/Elapsed: (.+)/);
        if (elapsedMatch) {
            status.elapsed = elapsedMatch[1].trim();
            status.elapsedSeconds = this.parseElapsedTimeToSeconds(elapsedMatch[1].trim());
        }

        return status;
    }

    private async getFlashStatus(workspacePath: string): Promise<FlashStatus> {
        try {
            const { stdout } = await execWithTimeout('make firmware-flash-status', { cwd: workspacePath, timeout: 10000 });
            return this.parseFlashStatusOutput(stdout);
        } catch (error: any) {
            if (error?.stdout) {
                return this.parseFlashStatusOutput(error.stdout);
            }
            return { running: false };
        }
    }

    private async getCostData(workspacePath: string): Promise<CostData> {
        try {
            const { stdout } = await execWithTimeout('make firmware-ec2-costs', { cwd: workspacePath, timeout: 15000 });
            return JSON.parse(stdout.trim());
        } catch (error: any) {
            return { runs: [], total_duration_secs: 0, total_cost: 0, hourly_rate: 0, error: 'Failed to load' };
        }
    }

    private formatRelativeTime(timestamp: number): string {
        const now = Date.now() / 1000;
        const diff = now - timestamp;
        if (diff < 60) return `${Math.floor(diff)}s ago`;
        if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
        if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
        return `${Math.floor(diff / 86400)}d ago`;
    }

    private formatDurationShort(secs: number): string {
        if (secs < 60) return `${secs}s`;
        if (secs < 3600) return `${Math.floor(secs / 60)}m`;
        const h = Math.floor(secs / 3600);
        const m = Math.floor((secs % 3600) / 60);
        return m > 0 ? `${h}h ${m}m` : `${h}h`;
    }

    public dispose() {
        YoctoBuilderPanel.currentPanel = undefined;
        this._panel.dispose();
        while (this._disposables.length) {
            const x = this._disposables.pop();
            if (x) {
                x.dispose();
            }
        }
    }
}

export function deactivate() { }

