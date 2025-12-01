import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import { exec, ChildProcess } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

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
    usbDeviceDetected?: boolean;
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
            vscode.commands.registerCommand('yocto-builder.flashStart', () => {
                outputChannel.appendLine('Command: flashStart');
                runCommand('make firmware-controller-flash C=steamdeck', 'Yocto Builder - Flash Start');
            }),
            vscode.commands.registerCommand('yocto-builder.flashWatch', () => {
                outputChannel.appendLine('Command: flashWatch');
                runCommand('make firmware-controller-flash-watch C=steamdeck', 'Yocto Builder - Flash Watch');
            }),
            vscode.commands.registerCommand('yocto-builder.flashTerminate', () => {
                outputChannel.appendLine('Command: flashTerminate');
                runCommand('make firmware-controller-flash-terminate C=steamdeck', 'Yocto Builder - Flash Terminate');
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

        this._panel.onDidDispose(() => this.dispose(), null, this._disposables);
        this._panel.webview.onDidReceiveMessage(
            async message => {
                switch (message.command) {
                    case 'instanceStart':
                        runCommand('make firmware-ec2-start', 'Yocto Builder - Start');
                        // Sync auto-stop preference to server after instance starts (silently, no terminal)
                        const autoStopPref = this._context.globalState.get<boolean>('autoStopOnBuildComplete', false);
                        if (autoStopPref) {
                            const wsFolder = vscode.workspace.workspaceFolders?.[0];
                            if (wsFolder) {
                                setTimeout(async () => {
                                    try {
                                        const instanceStatus = await this.getInstanceStatus(wsFolder.uri.fsPath);
                                        if (instanceStatus.state?.toLowerCase() === 'running') {
                                            // Run silently without opening a terminal, with timeout
                                            await execWithTimeout('make firmware-build-set-auto-stop', { cwd: wsFolder.uri.fsPath, timeout: 15000 });
                                        }
                                    } catch (error) {
                                        // Ignore errors (including timeouts)
                                    }
                                }, 5000); // Wait 5 seconds for instance to be ready
                            }
                        }
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
                        // Sync auto-stop preference to server after instance starts (silently, no terminal)
                        const autoStopPreference = this._context.globalState.get<boolean>('autoStopOnBuildComplete', false);
                        if (autoStopPreference) {
                            const wsFolder = vscode.workspace.workspaceFolders?.[0];
                            if (wsFolder) {
                                // Wait a bit for instance to start, then sync preference silently
                                setTimeout(async () => {
                                    try {
                                        const instanceStatus = await this.getInstanceStatus(wsFolder.uri.fsPath);
                                        if (instanceStatus.state?.toLowerCase() === 'running') {
                                            // Run silently without opening a terminal, with timeout
                                            await execWithTimeout('make firmware-build-set-auto-stop', { cwd: wsFolder.uri.fsPath, timeout: 15000 });
                                        }
                                    } catch (error) {
                                        // Ignore errors (including timeouts)
                                    }
                                }, 10000); // Wait 10 seconds for instance to be ready
                            }
                        }
                        break;
                    case 'buildWatch':
                        runCommand('make firmware-build-watch', 'Yocto Builder - Watch');
                        break;
                    case 'buildTerminate':
                        runCommand('make firmware-build-terminate', 'Yocto Builder - Terminate');
                        break;
                    case 'flashStart':
                        const flashMode = message.mode || 'bootloader';
                        const flashCommand = `make firmware-controller-flash C=steamdeck MODE=${flashMode}`;
                        runCommand(flashCommand, 'Yocto Builder - Flash Start');
                        break;
                    case 'toggleFlashMode':
                        this._context.globalState.update('flashMode', message.value || 'bootloader');
                        this.update();
                        break;
                    case 'flashWatch':
                        runCommand('make firmware-controller-flash-watch C=steamdeck', 'Yocto Builder - Flash Watch');
                        break;
                    case 'flashTerminate':
                        runCommand('make firmware-controller-flash-terminate C=steamdeck', 'Yocto Builder - Flash Terminate');
                        break;
                    case 'toggleStopOnComplete':
                        // Store preference locally (works even when instance is not running)
                        this._context.globalState.update('autoStopOnBuildComplete', message.value || false);

                        // If instance is running, sync to server immediately (silently, no terminal)
                        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
                        if (workspaceFolder) {
                            try {
                                const instanceStatus = await this.getInstanceStatus(workspaceFolder.uri.fsPath);
                                if (instanceStatus.state?.toLowerCase() === 'running') {
                                    if (message.value) {
                                        // Run silently without opening a terminal, with timeout
                                        await execWithTimeout('make firmware-build-set-auto-stop', { cwd: workspaceFolder.uri.fsPath, timeout: 15000 });
                                    } else {
                                        // Run silently without opening a terminal, with timeout
                                        await execWithTimeout('make firmware-build-unset-auto-stop', { cwd: workspaceFolder.uri.fsPath, timeout: 15000 });
                                    }
                                }
                            } catch (error) {
                                // Instance not running, that's okay - preference is stored locally
                            }
                        }
                        // Update UI to reflect change
                        this.update();
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
            this._previousBuildRunning = buildStatus.running;
        }

        const webview = this._panel.webview;
        this._panel.webview.html = await this._getHtmlForWebview(webview);
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
        const [instanceStatus, buildStatus, controllerStatus, flashStatus] = await Promise.all([
            this.getInstanceStatus(workspaceFolder.uri.fsPath),
            this.getBuildStatus(workspaceFolder.uri.fsPath),
            this.getControllerStatus(workspaceFolder.uri.fsPath),
            this.getFlashStatus(workspaceFolder.uri.fsPath)
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

        html = html.replace(/\{\{BUILD_STATUS_CLASS\}\}/g, buildStatus.running ? 'running' : 'stopped');
        html = html.replace(/\{\{BUILD_STATUS_TEXT\}\}/g, buildStatus.running ? 'Running' : 'Not Running');
        // Disable Start Build only if build is already running (instance will auto-start via Makefile)
        html = html.replace(/\{\{BUILD_START_DISABLED\}\}/g, buildStatus.running ? 'disabled' : '');
        // Disable Watch/Terminate if build is not running
        html = html.replace(/\{\{BUILD_WATCH_DISABLED\}\}/g, !buildStatus.running ? 'disabled' : '');
        html = html.replace(/\{\{BUILD_TERMINATE_DISABLED\}\}/g, !buildStatus.running ? 'disabled' : '');

        // Stop on build complete option (always visible and selectable)
        // Check server-side flag file status if instance is running, otherwise use local preference
        let autoStopEnabled = false;
        const localPreference = this._context.globalState.get<boolean>('autoStopOnBuildComplete', false);

        if (instanceRunning) {
            try {
                const { stdout } = await execWithTimeout('make firmware-build-check-auto-stop', { cwd: workspaceFolder.uri.fsPath, timeout: 15000 });
                autoStopEnabled = stdout.includes('enabled') || stdout.trim() === '1';
                // Sync local preference if server has different value
                if (autoStopEnabled !== localPreference) {
                    this._context.globalState.update('autoStopOnBuildComplete', autoStopEnabled);
                }
            } catch (error) {
                // If command fails or times out, use local preference
                autoStopEnabled = localPreference;
            }
        } else {
            // Instance not running, use local preference
            autoStopEnabled = localPreference;
        }

        const stopOnCompleteHtml = `
        <div class="stop-on-complete">
            <label>
                <input type="checkbox" id="stopOnComplete" ${autoStopEnabled ? 'checked' : ''} onchange="toggleStopOnComplete(this.checked)">
                Stop instance when build ends
            </label>
        </div>
        `;
        html = html.replace(/\{\{STOP_ON_COMPLETE\}\}/g, stopOnCompleteHtml);

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
        const usbDeviceDetected = flashStatus.usbDeviceDetected === true;
        const flashStartDisabled = flashStatus.running || !usbDeviceDetected;
        html = html.replace(/\{\{FLASH_START_DISABLED\}\}/g, flashStartDisabled ? 'disabled' : '');
        html = html.replace(/\{\{FLASH_WATCH_DISABLED\}\}/g, !flashStatus.running ? 'disabled' : '');
        html = html.replace(/\{\{FLASH_TERMINATE_DISABLED\}\}/g, !flashStatus.running ? 'disabled' : '');

        // Flash elapsed time section
        const flashElapsedHtml = flashStatus.elapsed ? `
        <div class="info-row">
            <span class="info-label">Elapsed:</span>
            <span id="flashElapsedTime" data-elapsed-seconds="${flashStatus.elapsedSeconds || 0}" data-is-running="${flashStatus.running}">${flashStatus.elapsed}</span>
        </div>
        ` : '';
        html = html.replace(/\{\{FLASH_ELAPSED_TIME\}\}/g, flashElapsedHtml);

        // Flash device status section
        const flashDeviceHtml = flashStatus.usbDeviceDetected !== undefined ? `
        <div class="info-row">
            <span class="info-label">USB Device:</span>
            <span style="display: flex; align-items: center; gap: 6px;">
                ${flashStatus.usbDeviceDetected ? '<div class="status-indicator running" style="width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0;"></div>' : '<div class="status-indicator stopped" style="width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0;"></div>'}
                ${flashStatus.usbDeviceDetected ? 'NVIDIA device detected' : 'No NVIDIA device'}
            </span>
        </div>
        ` : '';
        html = html.replace(/\{\{FLASH_DEVICE_STATUS\}\}/g, flashDeviceHtml);

        // Flash mode toggle (bootloader vs rootfs)
        const flashMode = this._context.globalState.get<string>('flashMode', 'bootloader');
        const flashRunning = flashStatus.running;
        const modeDisabled = flashRunning || !usbDeviceDetected;
        const flashModeHtml = `
        <div class="stop-on-complete" style="margin-top: 8px;">
            <label style="display: block; margin-bottom: 4px; font-weight: bold;">Flash Target:</label>
            <label style="display: flex; align-items: center; gap: 6px; cursor: ${modeDisabled ? 'not-allowed' : 'pointer'}; opacity: ${modeDisabled ? '0.6' : '1'};">
                <input type="radio" name="flashMode" value="bootloader" ${flashMode === 'bootloader' ? 'checked' : ''}
                    ${modeDisabled ? 'disabled' : ''} onchange="updateFlashMode('bootloader')">
                Bootloader (SPI)
            </label>
            <label style="display: flex; align-items: center; gap: 6px; cursor: ${modeDisabled ? 'not-allowed' : 'pointer'}; opacity: ${modeDisabled ? '0.6' : '1'};">
                <input type="radio" name="flashMode" value="rootfs" ${flashMode === 'rootfs' ? 'checked' : ''}
                    ${modeDisabled ? 'disabled' : ''} onchange="updateFlashMode('rootfs')">
                Rootfs (NVMe)
            </label>
        </div>
        `;
        html = html.replace(/\{\{FLASH_MODE_TOGGLE\}\}/g, flashModeHtml);

        return html;
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
            const { stdout } = await execWithTimeout('make firmware-controller-flash-status C=steamdeck', { cwd: workspacePath, timeout: 10000 });
            const status = this.parseFlashStatusOutput(stdout);

            // Check USB device status on controller
            try {
                const controllerStatus = await this.getControllerStatus(workspacePath);
                if (controllerStatus.reachable) {
                    try {
                        const { stdout: usbStdout } = await execWithTimeout(
                            'make firmware-controller-usb-device C=steamdeck',
                            { cwd: workspacePath, timeout: 5000 }
                        );
                        status.usbDeviceDetected = usbStdout.trim() === 'detected';
                    } catch (usbError) {
                        status.usbDeviceDetected = false;
                    }
                }
            } catch (controllerError) {
                // If we can't check controller, USB device status is unknown
            }

            return status;
        } catch (error: any) {
            if (error?.stdout) {
                return this.parseFlashStatusOutput(error.stdout);
            }
            return { running: false };
        }
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

