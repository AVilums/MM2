from helper.gui import ManualMode

def main():
    try:
        app = ManualMode()

    except Exception as e:
        print('Fatal error {e} \n')
        return 0
    
    return 1
    
if __name__ == "__main__":
    main()