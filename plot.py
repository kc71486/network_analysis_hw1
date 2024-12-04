import matplotlib.pyplot as plt

# copy from other people

# 繪製圖表的函數
def plot():
    buffer_sizes = [20, 40, 60, 80, 100] 
    loss_ratios = []
    utilizations = []
    with open("result2.txt") as f:
        for lines in f:
            if len(lines) == 0:
                continue
            entry = lines.split(" ")
            loss_ratios.append(float(entry[0]))
            utilizations.append(float(entry[1]))

    # 繪製圖表
    plt.figure(figsize=(12, 5))
    
    # 影格遺失率圖表
    plt.subplot(1, 2, 1)
    plt.plot(buffer_sizes, loss_ratios, 'bo-')
    plt.xlabel('Buffer Size (β)')
    plt.ylabel('Frame Loss Ratio (f)')
    plt.ylim([0, 1])
    plt.title('Frame Loss Ratio vs Buffer Size')
    plt.grid(True)
    
    # 儲存伺服器使用率圖表
    plt.subplot(1, 2, 2)
    plt.plot(buffer_sizes, utilizations, 'ro-')
    plt.xlabel('Buffer Size (β)')
    plt.ylabel('Storage Server Utilization (u)')
    plt.ylim([0, 1])
    plt.title('Storage Server Utilization vs Buffer Size')
    plt.grid(True)
    
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    # 設定隨機數種子以確保結果可重現
    plot()
